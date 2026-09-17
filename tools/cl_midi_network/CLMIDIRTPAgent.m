#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>
#import <signal.h>
#import <fcntl.h>

static volatile sig_atomic_t keepRunning = 1;
static void stopAgent(int value) { (void)value; keepRunning = 0; }

static void installLoginLaunchAgent(void) {
    NSString *executable = NSProcessInfo.processInfo.arguments.firstObject;
    if (!executable.length) return;
    executable = executable.stringByStandardizingPath;
    NSString *agentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    NSString *plistPath = [agentsDirectory stringByAppendingPathComponent:@"com.claudio.midi-rtp-agent.plist"];
    NSDictionary *configuration = @{
        @"Label": @"com.claudio.midi-rtp-agent",
        @"ProgramArguments": @[executable],
        @"RunAtLoad": @YES,
        @"KeepAlive": @YES,
        @"ThrottleInterval": @5,
        @"ProcessType": @"Background"
    };
    [NSFileManager.defaultManager createDirectoryAtPath:agentsDirectory
                            withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:configuration
                                                               format:NSPropertyListXMLFormat_v1_0
                                                              options:0 error:nil];
    if (plist.length) [plist writeToFile:plistPath options:NSDataWritingAtomic error:nil];
}

static NSString *argumentValue(NSArray<NSString *> *arguments, NSString *name, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:name];
    return index != NSNotFound && index + 1 < arguments.count ? arguments[index + 1] : fallback;
}

static NSString *directBridgePath(void) {
    NSString *executable = NSProcessInfo.processInfo.arguments.firstObject.stringByStandardizingPath;
    NSString *directory = executable.stringByDeletingLastPathComponent;
    NSString *candidate = [directory stringByAppendingPathComponent:@"CLMIDIDirectBridge"];

    if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) {
        return candidate;
    }

    return nil;
}

static NSTask *startDirectBridge(
    NSString *host,
    uint16_t port,
    NSString *peerName,
    NSString *endpointName
) {
    NSString *bridge = directBridgePath();

    if (!bridge.length) {
        NSLog(@"DIRECT_RTP bridge introuvable");
        return nil;
    }

    NSTask *task = [[NSTask alloc] init];

    task.executableURL = [NSURL fileURLWithPath:bridge];

    task.arguments = @[
        @"--host", host,
        @"--port", [NSString stringWithFormat:@"%u", port],
        @"--peer-name", peerName,
        @"--endpoint", endpointName
    ];

    NSError *error = nil;

    if (![task launchAndReturnError:&error]) {
        NSLog(@"DIRECT_RTP lancement impossible: %@", error.localizedDescription);
        return nil;
    }

    NSLog(
        @"DIRECT_RTP lancé pid=%d host=%@ port=%u",
        task.processIdentifier,
        host,
        port
    );

    return task;
}

static void stopDirectBridge(NSTask *task) {
    if (task && task.isRunning) {
        [task terminate];
    }
}

@interface CLBonjourResolver : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic, strong) NSNetServiceBrowser *browser;
@property(nonatomic, strong) NSNetService *resolvedService;
@property(nonatomic, copy) NSString *targetName;
@property(nonatomic, copy) NSString *resolvedHost;
@property(nonatomic, assign) NSInteger resolvedPort;
@property(nonatomic, assign) BOOL finished;
@end

@implementation CLBonjourResolver

- (instancetype)initWithTargetName:(NSString *)targetName {
    self = [super init];

    if (self) {
        _targetName = [targetName copy];
        _resolvedPort = 0;
        _finished = NO;
    }

    return self;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    (void)browser;
    (void)moreComing;

    if (![service.name isEqualToString:self.targetName]) {
        return;
    }

    self.resolvedService = service;
    service.delegate = self;

    [service resolveWithTimeout:2.0];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    for (NSData *addressData in service.addresses) {
        const struct sockaddr *address =
            (const struct sockaddr *)addressData.bytes;

        if (!address) {
            continue;
        }

        if (address->sa_family == AF_INET) {
            const struct sockaddr_in *ipv4 =
                (const struct sockaddr_in *)address;

            char buffer[INET_ADDRSTRLEN] = {0};

            if (
                inet_ntop(
                    AF_INET,
                    &ipv4->sin_addr,
                    buffer,
                    sizeof(buffer)
                )
            ) {
                self.resolvedHost =
                    [NSString stringWithUTF8String:buffer];

                self.resolvedPort =
                    service.port;

                self.finished = YES;

                [self.browser stop];

                return;
            }
        }
    }
}

- (void)netService:(NSNetService *)sender
     didNotResolve:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    (void)sender;
    (void)errorDict;

    self.finished = YES;

    [self.browser stop];
}

@end

static NSDictionary *resolveBonjourPeer(
    NSString *serviceName,
    NSTimeInterval timeout
) {
    CLBonjourResolver *resolver =
        [[CLBonjourResolver alloc] initWithTargetName:serviceName];

    resolver.browser =
        [[NSNetServiceBrowser alloc] init];

    resolver.browser.delegate =
        resolver;

    [resolver.browser
        searchForServicesOfType:@"_apple-midi._udp."
        inDomain:@"local."];

    NSDate *deadline =
        [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (
        !resolver.finished &&
        [deadline timeIntervalSinceNow] > 0
    ) {
        [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode
            beforeDate:
                [NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    [resolver.browser stop];

    if (
        resolver.resolvedHost.length &&
        resolver.resolvedPort > 0
    ) {
        return @{
            @"host": resolver.resolvedHost,
            @"port": @(resolver.resolvedPort),
            @"name": serviceName
        };
    }

    return nil;
}

static MIDINetworkHost *bonjourHost(NSString *name) {
    return [MIDINetworkHost hostWithName:name netServiceName:name netServiceDomain:@"local."];
}

static BOOL connectionMatches(MIDINetworkConnection *connection, NSString *name) {
    MIDINetworkHost *host = connection.host;
    return [host.name isEqualToString:name] || [host.netServiceName isEqualToString:name];
}

static void ensurePeer(MIDINetworkSession *session, NSString *name) {
    for (MIDINetworkConnection *connection in session.connections) {
        if (connectionMatches(connection, name)) return;
    }
    MIDINetworkHost *host = bonjourHost(name);
    [session addContact:host];
    [session addConnection:[MIDINetworkConnection connectionWithHost:host]];
}

static void broadcastStatus(int socketFD, MIDINetworkSession *session, NSArray<NSString *> *targets, uint16_t port) {
    NSMutableArray<NSString *> *connections = [NSMutableArray array];
    for (MIDINetworkConnection *connection in session.connections) {
        MIDINetworkHost *host = connection.host;
        [connections addObject:host.netServiceName ?: host.name ?: host.address ?: @"inconnu"];
    }
    NSDictionary *payload = @{
        @"service": @"cl-midi-rtp-agent", @"role": @"ableton-reader",
        @"host": NSHost.currentHost.localizedName ?: NSProcessInfo.processInfo.hostName ?: @"",
        @"session_enabled": @(session.isEnabled), @"session_name": session.localName ?: @"",
        @"targets": targets, @"connections": connections,
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data.length) return;
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address); address.sin_family = AF_INET;
    address.sin_port = htons(port); address.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    sendto(socketFD, data.bytes, data.length, 0, (struct sockaddr *)&address, sizeof(address));
}

static NSDictionary *handleControlCommand(NSDictionary *command) {
    if (![command[@"service"] isEqualToString:@"cl-midi-rtp-control"]) return nil;
    NSString *action = command[@"action"];
    NSString *bundleID = @"com.claudio.midi-rtp-simulator";
    if ([action isEqualToString:@"status-simulator"]) {
        NSArray<NSString *> *candidates = @[[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/CL MIDI RTP Simulator.app"], @"/Applications/CL MIDI RTP Simulator.app"];
        BOOL installed = NO;
        for (NSString *candidate in candidates) if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) { installed = YES; break; }
        BOOL running = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID].count > 0;
        return @{@"ok": @YES, @"agent": @YES, @"installed": @(installed), @"running": @(running),
                 @"message": installed ? (running ? @"Simulateur distant actif" : @"Simulateur distant prêt") : @"Simulateur absent sur le Mac distant"};
    }
    if ([action isEqualToString:@"start-simulator"]) {
        NSArray<NSString *> *candidates = @[
            [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/CL MIDI RTP Simulator.app"],
            @"/Applications/CL MIDI RTP Simulator.app"
        ];
        NSString *appPath = nil;
        for (NSString *candidate in candidates) if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) { appPath = candidate; break; }
        if (!appPath) return @{@"ok": @NO, @"message": @"Simulateur absent sur le Mac distant"};
        BOOL opened = [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:appPath]];
        return @{@"ok": @(opened), @"message": opened ? @"Simulateur distant démarré" : @"Impossible de démarrer le simulateur distant"};
    }
    if ([action isEqualToString:@"stop-simulator"]) {
        NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
        for (NSRunningApplication *app in apps) [app terminate];
        return @{@"ok": @YES, @"message": @"Simulateur distant arrêté"};
    }
    return @{@"ok": @NO, @"message": @"Commande distante inconnue"};
}

static void receiveControlCommands(int socketFD) {
    for (;;) {
        UInt8 buffer[4096]; struct sockaddr_in sender = {0}; socklen_t senderLength = sizeof(sender);
        ssize_t length = recvfrom(socketFD, buffer, sizeof(buffer), 0, (struct sockaddr *)&sender, &senderLength);
        if (length <= 0) break;
        NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)length];
        NSDictionary *command = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *response = [command isKindOfClass:NSDictionary.class] ? handleControlCommand(command) : nil;
        if (!response) continue;
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        sendto(socketFD, encoded.bytes, encoded.length, 0, (struct sockaddr *)&sender, senderLength);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        installLoginLaunchAgent();
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        NSString *targetsValue = argumentValue(arguments, @"--targets", @"CL5,QL1");
        uint16_t statusPort = (uint16_t)[argumentValue(arguments, @"--status-port", @"50021") integerValue];

        NSString *directPeerHost = argumentValue(arguments, @"--direct-peer-host", @"");
        uint16_t directPeerPort = (uint16_t)[argumentValue(arguments, @"--direct-peer-port", @"5006") integerValue];
        NSString *directPeerName = argumentValue(arguments, @"--direct-peer-name", @"CL Ableton Distant");
        NSString *directEndpointName = argumentValue(arguments, @"--direct-endpoint", @"CL Direct RTP");

        BOOL directMode =
            directPeerHost.length > 0 ||
            directPeerName.length > 0;

        if (
            directMode &&
            directPeerHost.length == 0
        ) {
            NSDictionary *resolved =
                resolveBonjourPeer(
                    directPeerName,
                    3.0
                );

            if (resolved) {
                directPeerHost =
                    resolved[@"host"];

                NSNumber *resolvedPort =
                    resolved[@"port"];

                if (
                    resolvedPort &&
                    resolvedPort.unsignedIntegerValue > 0
                ) {
                    directPeerPort =
                        (uint16_t)
                        resolvedPort.unsignedIntegerValue;
                }

                NSLog(
                    @"DIRECT_RTP Bonjour %@ -> %@:%u",
                    directPeerName,
                    directPeerHost,
                    directPeerPort
                );
            } else {
                NSLog(
                    @"DIRECT_RTP Bonjour introuvable: %@",
                    directPeerName
                );

                directMode = NO;
            }
        }
        NSMutableArray<NSString *> *targets = [NSMutableArray array];
        for (NSString *part in [targetsValue componentsSeparatedByString:@","]) {
            NSString *name = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (name.length) [targets addObject:name];
        }
        signal(SIGINT, stopAgent); signal(SIGTERM, stopAgent);
        MIDIClientRef client = 0;
        if (MIDIClientCreate(CFSTR("CL MIDI RTP Agent"), NULL, NULL, &client) != noErr) return 2;
        MIDINetworkSession *session = MIDINetworkSession.defaultSession;
        session.enabled = YES; session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
        NSString *publishedName = session.localName.length ? session.localName : (NSHost.currentHost.localizedName ?: NSProcessInfo.processInfo.hostName);
        NSNetService *controlService = [[NSNetService alloc] initWithDomain:@"local."
                                                                       type:@"_cl-midi-rtp-control._udp."
                                                                       name:publishedName
                                                                       port:50022];
        [controlService publish];
        int socketFD = socket(AF_INET, SOCK_DGRAM, 0), enabled = 1;
        if (socketFD >= 0) setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &enabled, sizeof(enabled));
        int controlFD = socket(AF_INET, SOCK_DGRAM, 0);
        if (controlFD >= 0) {
            setsockopt(controlFD, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
            struct sockaddr_in controlAddress = {0};
            controlAddress.sin_len = sizeof(controlAddress); controlAddress.sin_family = AF_INET;
            controlAddress.sin_port = htons(50022); controlAddress.sin_addr.s_addr = htonl(INADDR_ANY);
            if (bind(controlFD, (struct sockaddr *)&controlAddress, sizeof(controlAddress)) != 0) { close(controlFD); controlFD = -1; }
            else fcntl(controlFD, F_SETFL, O_NONBLOCK);
        }

        NSTask *directTask = nil;

        if (directMode) {
            directTask = startDirectBridge(
                directPeerHost,
                directPeerPort,
                directPeerName,
                directEndpointName
            );
        }

        while (keepRunning) {
            if (controlFD >= 0) receiveControlCommands(controlFD);

            if (directMode) {
                if (!directTask || !directTask.isRunning) {
                    directTask = startDirectBridge(
                        directPeerHost,
                        directPeerPort,
                        directPeerName,
                        directEndpointName
                    );
                }
            } else {
                for (NSString *target in targets) ensurePeer(session, target);
            }

            if (socketFD >= 0) broadcastStatus(socketFD, session, targets, statusPort);
            for (NSUInteger tick = 0; tick < 20 && keepRunning; tick++) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
        stopDirectBridge(directTask);
        [controlService stop];
        if (socketFD >= 0) close(socketFD);
        if (controlFD >= 0) close(controlFD);
        MIDIClientDispose(client);
    }
    return 0;
}

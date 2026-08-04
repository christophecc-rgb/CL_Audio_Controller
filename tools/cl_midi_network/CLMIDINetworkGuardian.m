#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <signal.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

static volatile sig_atomic_t keepRunning = 1;

static void stopHandler(int signalValue) {
    (void)signalValue;
    keepRunning = 0;
}

static NSString *argumentValue(NSArray<NSString *> *arguments, NSString *name, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:name];
    if (index != NSNotFound && index + 1 < arguments.count) {
        return arguments[index + 1];
    }
    return fallback;
}

static BOOL hasFlag(NSArray<NSString *> *arguments, NSString *name) {
    return [arguments containsObject:name];
}

static void printStatus(MIDINetworkSession *session, NSString *peerName, NSString *event) {
    NSMutableArray<NSString *> *peers = [NSMutableArray array];
    for (MIDINetworkConnection *connection in session.connections) {
        MIDINetworkHost *host = connection.host;
        [peers addObject:host.netServiceName ?: host.name ?: host.address ?: @"unknown"];
    }
    NSDictionary *payload = @{
        @"event": event,
        @"session_enabled": @(session.isEnabled),
        @"session_name": session.localName ?: @"",
        @"network_name": session.networkName ?: @"",
        @"network_port": @(session.networkPort),
        @"expected_peer": peerName,
        @"connections": peers,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
    fflush(stdout);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        int singletonLock = open("/private/tmp/CL_MIDI_Network_Guardian.lock", O_CREAT | O_RDWR, 0600);
        if (singletonLock < 0 || flock(singletonLock, LOCK_EX | LOCK_NB) != 0) return 0;
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        if (hasFlag(arguments, @"--help")) {
            puts("Usage: CLMIDINetworkGuardian --peer-name NAME [--peer-host HOST] [--peer-port 5004] [--once]");
            return 0;
        }

        NSString *peerName = argumentValue(arguments, @"--peer-name", @"MB Pro");
        NSString *peerHost = argumentValue(arguments, @"--peer-host", @"");
        NSUInteger peerPort = (NSUInteger)[argumentValue(arguments, @"--peer-port", @"5004") integerValue];
        NSTimeInterval interval = [argumentValue(arguments, @"--interval", @"2") doubleValue];
        BOOL once = hasFlag(arguments, @"--once");

        signal(SIGINT, stopHandler);
        signal(SIGTERM, stopHandler);

        // Force CoreMIDI to load the installed drivers before asking for the
        // singleton network session.  On machines upgraded from older macOS
        // releases, querying MIDINetworkSession before creating a client can
        // otherwise expose an empty session while the legacy RTP endpoint is
        // already visible to MIDI applications.
        MIDIClientRef midiClient = 0;
        OSStatus clientStatus = MIDIClientCreate(CFSTR("CL MIDI Network Guardian"),
                                                 NULL, NULL, &midiClient);
        if (clientStatus != noErr) {
            fprintf(stderr, "CoreMIDI client creation failed: %d\n", (int)clientStatus);
            return 2;
        }

        MIDINetworkSession *session = [MIDINetworkSession defaultSession];
        session.enabled = YES;
        session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;

        MIDINetworkHost *host = nil;
        if (peerHost.length > 0) {
            host = [MIDINetworkHost hostWithName:peerName address:peerHost port:peerPort];
        } else {
            host = [MIDINetworkHost hostWithName:peerName
                                  netServiceName:peerName
                                netServiceDomain:@"local."];
        }
        [session addContact:host];

        while (keepRunning) {
            BOOL connected = NO;
            for (MIDINetworkConnection *connection in session.connections) {
                if ([connection.host hasSameAddressAs:host] ||
                    [connection.host.name isEqualToString:peerName] ||
                    [connection.host.netServiceName isEqualToString:peerName]) {
                    connected = YES;
                    break;
                }
            }
            if (!connected) {
                MIDINetworkConnection *connection = [MIDINetworkConnection connectionWithHost:host];
                BOOL accepted = [session addConnection:connection];
                printStatus(session, peerName, accepted ? @"connect-requested" : @"connect-request-rejected");
            } else {
                printStatus(session, peerName, @"connected");
            }
            if (once) break;
            // MIDINetworkSession completes Bonjour/RTP invitations
            // asynchronously, so keep a run loop active between retries.
            [[NSRunLoop currentRunLoop] runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:MAX(0.5, interval)]];
        }
        printStatus(session, peerName, @"stopped");
        MIDIClientDispose(midiClient);
    }
    return 0;
}

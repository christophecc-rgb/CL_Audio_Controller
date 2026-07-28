#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <sys/socket.h>
#import <unistd.h>

static const UInt16 CLSceneContextPort = 9002;

static NSString *CLReadOSCString(NSData *data, NSUInteger *offset) {
    const UInt8 *bytes = data.bytes;
    NSUInteger length = data.length;
    if (*offset >= length) return nil;
    NSUInteger end = *offset;
    while (end < length && bytes[end] != 0) end++;
    if (end >= length) return nil;
    NSString *value = [[NSString alloc] initWithBytes:bytes + *offset length:end - *offset encoding:NSUTF8StringEncoding];
    *offset = (end + 4) & ~((NSUInteger)3);
    return value;
}

static NSString *EndpointName(MIDIEndpointRef endpoint) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || value == NULL) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    }
    return CFBridgingRelease(value) ?: @"";
}

static NSArray<NSString *> *EndpointNames(BOOL sources) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    ItemCount count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
    for (ItemCount index = 0; index < count; index++) {
        MIDIEndpointRef endpoint = sources ? MIDIGetSource(index) : MIDIGetDestination(index);
        NSString *name = EndpointName(endpoint);
        if (name.length) [names addObject:name];
    }
    return names.array;
}

@interface CLNetworkDelegate : NSObject <NSApplicationDelegate, NSNetServiceBrowserDelegate>
@property NSWindow *window;
@property NSView *lamp;
@property NSTextField *headline;
@property NSTextField *detail;
@property NSTextField *sessionInfo;
@property NSTextField *lastTest;
@property NSPopUpButton *endpointMenu;
@property NSTextField *programField;
@property NSPopUpButton *testTargetMenu;
@property NSButton *testButton;
@property NSPopUpButton *targetMenu;
@property NSButton *connectButton;
@property NSTimer *timer;
@property NSTimer *statusTimer;
@property BOOL statusRequestRunning;
@property NSNetServiceBrowser *serviceBrowser;
@property NSMutableOrderedSet<NSString *> *discoveredPeers;
@property NSString *localNetworkName;
@property BOOL peerInspectionRunning;
@property NSString *validatedEndpoint;
@property NSDate *validatedAt;
@property NSTask *simulatorDashboardTask;
@property NSTextField *monitorStatus;
@property NSTextField *cl5Program;
@property NSTextField *cl5Detail;
@property NSTextField *cl5Scene;
@property NSTextField *ql1Program;
@property NSTextField *ql1Detail;
@property NSTextField *ql1Scene;
@property NSTextField *ltcTimecode;
@property MIDIClientRef monitorClient;
@property MIDIPortRef monitorInputPort;
@property MIDIEndpointRef monitorSource;
@property NSInteger pendingCL5Program;
@property NSInteger pendingQL1Program;
@property NSInteger lastCL5Program;
@property NSInteger lastQL1Program;
@property CFAbsoluteTime lastCL5ProgramAt;
@property CFAbsoluteTime lastQL1ProgramAt;
@property BOOL returnUpdateScheduled;
@property int sceneSocket;
@property dispatch_source_t sceneSource;
@property NSString *currentSceneName;
- (void)writePublishedConsoleState;
- (void)queueProgram:(UInt8)program channel:(UInt8)channel;
- (void)handleProgram:(UInt8)program channel:(UInt8)channel;
- (void)handleSceneDatagram:(NSData *)data;
@end

static void CLReturnMonitorRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)srcConnRefCon;
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 status = packet->data[index];
            if ((status & 0xF0) == 0xC0 && index + 1 < packet->length) {
                UInt8 program = packet->data[index + 1];
                UInt8 channel = (status & 0x0F) + 1;
                [delegate queueProgram:program channel:channel];
                index += 2;
            } else {
                index += 1;
            }
        }
        packet = MIDIPacketNext(packet);
    }
}

@implementation CLNetworkDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.textColor = [NSColor colorWithWhite:0.76 alpha:1.0];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return label;
}

- (void)stylePopup:(NSPopUpButton *)popup accent:(NSColor *)accent {
    popup.font = [NSFont boldSystemFontOfSize:12.0];
    popup.contentTintColor = accent;
    popup.wantsLayer = YES;
    popup.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0].CGColor;
    popup.layer.cornerRadius = 8.0;
    popup.layer.borderWidth = 1.0;
    popup.layer.borderColor = [accent colorWithAlphaComponent:0.55].CGColor;
    for (NSMenuItem *item in popup.itemArray) {
        item.attributedTitle = [[NSAttributedString alloc] initWithString:item.title attributes:@{
            NSForegroundColorAttributeName: accent,
            NSFontAttributeName: [NSFont boldSystemFontOfSize:12.0]
        }];
    }
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    return button;
}

- (NSButton *)accentButton:(NSString *)title frame:(NSRect)frame action:(SEL)action color:(NSColor *)color {
    NSButton *button = [self button:title frame:frame action:action];
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.backgroundColor = color.CGColor;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [color blendedColorWithFraction:0.30 ofColor:NSColor.whiteColor].CGColor;
    button.layer.shadowColor = color.CGColor;
    button.layer.shadowOpacity = 0.22;
    button.layer.shadowRadius = 5.0;
    button.layer.shadowOffset = CGSizeMake(0, -1);
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12.0]
    }];
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 500)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI Network Assistant";
    self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.045 blue:0.060 alpha:1.0];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSView *content = self.window.contentView;

    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(16, 414, 448, 70)];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.023 blue:0.032 alpha:1.0].CGColor;
    header.layer.cornerRadius = 12.0;
    header.layer.borderWidth = 1.0;
    header.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor;
    [content addSubview:header];

    NSString *logoPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"paradis_latin_logo.jpg"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    NSImageView *logoView = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 10, 155, 50)];
    logoView.image = logo;
    logoView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [header addSubview:logoView];
    NSTextField *appTitle = [self label:@"CL MIDI NETWORK ASSISTANT" frame:NSMakeRect(182, 32, 250, 22) size:13 bold:YES];
    NSTextField *appSubtitle = [self label:@"Connexion RTP · validation Yamaha" frame:NSMakeRect(182, 13, 250, 18) size:10 bold:NO];
    appSubtitle.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
    [header addSubview:appTitle];
    [header addSubview:appSubtitle];

    self.lamp = [[NSView alloc] initWithFrame:NSMakeRect(24, 338, 34, 34)];
    self.lamp.wantsLayer = YES;
    self.lamp.layer.cornerRadius = 17;
    [content addSubview:self.lamp];
    self.headline = [self label:@"Analyse de la connexion RTP…" frame:NSMakeRect(70, 346, 385, 25) size:17 bold:YES];
    self.detail = [self label:@"" frame:NSMakeRect(70, 320, 385, 22) size:11 bold:NO];
    [content addSubview:self.headline];
    [content addSubview:self.detail];

    [content addSubview:[self label:@"CIBLE RTP DISTANTE" frame:NSMakeRect(24, 278, 190, 20) size:10 bold:YES]];
    self.targetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 244, 300, 30) pullsDown:NO];
    self.targetMenu.target = self;
    self.targetMenu.action = @selector(targetChanged:);
    [self.targetMenu addItemWithTitle:@"Recherche des correspondants…"];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    [content addSubview:self.targetMenu];
    self.connectButton = [self accentButton:@"Connecter" frame:NSMakeRect(334, 243, 122, 32) action:@selector(connectSelectedPeer:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.82 alpha:1.0]];
    [content addSubview:self.connectButton];

    [content addSubview:[self label:@"PORT RTP À TESTER" frame:NSMakeRect(24, 218, 190, 20) size:10 bold:YES]];
    self.endpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 184, 184, 30) pullsDown:NO];
    self.endpointMenu.target = self;
    self.endpointMenu.action = @selector(endpointChanged:);
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];
    [content addSubview:self.endpointMenu];
    [content addSubview:[self label:@"CONSOLE" frame:NSMakeRect(220, 218, 100, 20) size:10 bold:YES]];
    self.testTargetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(216, 184, 108, 30) pullsDown:NO];
    [self.testTargetMenu addItemsWithTitles:@[@"CL5 · Ch.1", @"QL1 · Ch.2"]];
    [self stylePopup:self.testTargetMenu accent:[NSColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:1.0]];
    [content addSubview:self.testTargetMenu];
    [content addSubview:[self label:@"PGM" frame:NSMakeRect(338, 218, 50, 20) size:10 bold:YES]];
    self.programField = [[NSTextField alloc] initWithFrame:NSMakeRect(334, 184, 60, 30)];
    self.programField.stringValue = @"42";
    self.programField.alignment = NSTextAlignmentCenter;
    self.programField.font = [NSFont boldSystemFontOfSize:14.0];
    self.programField.textColor = [NSColor colorWithRed:0.55 green:0.90 blue:0.68 alpha:1.0];
    self.programField.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0];
    [content addSubview:self.programField];
    self.testButton = [self accentButton:@"Tester" frame:NSMakeRect(402, 183, 54, 32) action:@selector(runTest:) color:[NSColor colorWithRed:0.08 green:0.58 blue:0.32 alpha:1.0]];
    [content addSubview:self.testButton];

    self.sessionInfo = [self label:@"" frame:NSMakeRect(24, 137, 432, 38) size:11 bold:NO];
    self.sessionInfo.maximumNumberOfLines = 2;
    self.lastTest = [self label:@"Aucun aller-retour validé" frame:NSMakeRect(24, 97, 432, 30) size:12 bold:YES];
    [content addSubview:self.sessionInfo];
    [content addSubview:self.lastTest];

    [content addSubview:[self accentButton:@"Réglages MIDI" frame:NSMakeRect(24, 35, 124, 36) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.16 green:0.25 blue:0.39 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Actualiser" frame:NSMakeRect(158, 35, 100, 36) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.20 green:0.25 blue:0.33 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Console Simulator" frame:NSMakeRect(268, 35, 188, 36) action:@selector(startSimulator:) color:[NSColor colorWithRed:0.68 green:0.35 blue:0.08 alpha:1.0]]];

    NSTextField *footer = [self label:@"CL AUDIO · MIDI NETWORK · 2026" frame:NSMakeRect(24, 8, 432, 18) size:9 bold:YES];
    footer.alignment = NSTextAlignmentCenter;
    footer.textColor = [NSColor colorWithWhite:0.38 alpha:1.0];
    [content addSubview:footer];

    NSView *monitorPanel = [[NSView alloc] initWithFrame:NSMakeRect(488, 16, 276, 468)];
    monitorPanel.wantsLayer = YES;
    monitorPanel.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.027 blue:0.038 alpha:1.0].CGColor;
    monitorPanel.layer.cornerRadius = 12.0;
    monitorPanel.layer.borderWidth = 1.0;
    monitorPanel.layer.borderColor = [NSColor colorWithRed:0.20 green:0.44 blue:0.60 alpha:0.75].CGColor;
    [content addSubview:monitorPanel];

    NSTextField *monitorTitle = [self label:@"RETOURS CONSOLES" frame:NSMakeRect(18, 424, 240, 24) size:14 bold:YES];
    monitorTitle.textColor = [NSColor colorWithRed:0.40 green:0.78 blue:1.0 alpha:1.0];
    [monitorPanel addSubview:monitorTitle];
    self.monitorStatus = [self label:@"Initialisation de l’écoute MIDI…" frame:NSMakeRect(18, 395, 240, 30) size:10 bold:NO];
    self.monitorStatus.maximumNumberOfLines = 2;
    [monitorPanel addSubview:self.monitorStatus];

    NSView *cl5Panel = [[NSView alloc] initWithFrame:NSMakeRect(16, 258, 244, 120)];
    cl5Panel.wantsLayer = YES;
    cl5Panel.layer.backgroundColor = [NSColor colorWithRed:0.035 green:0.09 blue:0.13 alpha:1.0].CGColor;
    cl5Panel.layer.cornerRadius = 10.0;
    cl5Panel.layer.borderWidth = 1.0;
    cl5Panel.layer.borderColor = [NSColor colorWithRed:0.22 green:0.65 blue:0.94 alpha:0.8].CGColor;
    [monitorPanel addSubview:cl5Panel];
    NSTextField *cl5Title = [self label:@"RETOUR PROGRAM CHANGE · CANAL 1" frame:NSMakeRect(14, 94, 218, 16) size:8 bold:YES];
    cl5Title.textColor = [NSColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:1.0];
    [cl5Panel addSubview:cl5Title];
    self.cl5Program = [self label:@"CL5 · N° —" frame:NSMakeRect(14, 61, 210, 29) size:18 bold:YES];
    self.cl5Program.alignment = NSTextAlignmentCenter;
    self.cl5Program.textColor = [NSColor colorWithRed:0.95 green:0.78 blue:0.30 alpha:1.0];
    [cl5Panel addSubview:self.cl5Program];
    self.cl5Scene = [self label:@"Titre en attente" frame:NSMakeRect(12, 37, 220, 20) size:10 bold:YES];
    self.cl5Scene.alignment = NSTextAlignmentCenter;
    self.cl5Scene.lineBreakMode = NSLineBreakByTruncatingTail;
    self.cl5Scene.textColor = [NSColor colorWithRed:0.65 green:0.84 blue:1.0 alpha:1.0];
    [cl5Panel addSubview:self.cl5Scene];
    self.cl5Detail = [self label:@"En attente d’un retour" frame:NSMakeRect(14, 10, 216, 18) size:8 bold:YES];
    self.cl5Detail.alignment = NSTextAlignmentCenter;
    [cl5Panel addSubview:self.cl5Detail];

    NSView *ql1Panel = [[NSView alloc] initWithFrame:NSMakeRect(16, 128, 244, 120)];
    ql1Panel.wantsLayer = YES;
    ql1Panel.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.075 blue:0.105 alpha:1.0].CGColor;
    ql1Panel.layer.cornerRadius = 10.0;
    ql1Panel.layer.borderWidth = 1.0;
    ql1Panel.layer.borderColor = [NSColor colorWithRed:0.38 green:0.60 blue:0.94 alpha:0.8].CGColor;
    [monitorPanel addSubview:ql1Panel];
    NSTextField *ql1Title = [self label:@"RETOUR PROGRAM CHANGE · CANAL 2" frame:NSMakeRect(14, 94, 218, 16) size:8 bold:YES];
    ql1Title.textColor = [NSColor colorWithRed:0.60 green:0.82 blue:1.0 alpha:1.0];
    [ql1Panel addSubview:ql1Title];
    self.ql1Program = [self label:@"QL1 · N° —" frame:NSMakeRect(14, 61, 210, 29) size:18 bold:YES];
    self.ql1Program.alignment = NSTextAlignmentCenter;
    self.ql1Program.textColor = [NSColor colorWithRed:0.95 green:0.78 blue:0.30 alpha:1.0];
    [ql1Panel addSubview:self.ql1Program];
    self.ql1Scene = [self label:@"Titre en attente" frame:NSMakeRect(12, 37, 220, 20) size:10 bold:YES];
    self.ql1Scene.alignment = NSTextAlignmentCenter;
    self.ql1Scene.lineBreakMode = NSLineBreakByTruncatingTail;
    self.ql1Scene.textColor = [NSColor colorWithRed:0.70 green:0.84 blue:1.0 alpha:1.0];
    [ql1Panel addSubview:self.ql1Scene];
    self.ql1Detail = [self label:@"En attente d’un retour" frame:NSMakeRect(14, 10, 216, 18) size:8 bold:YES];
    self.ql1Detail.alignment = NSTextAlignmentCenter;
    [ql1Panel addSubview:self.ql1Detail];

    NSView *ltcPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 54, 244, 64)];
    ltcPanel.wantsLayer = YES;
    ltcPanel.layer.backgroundColor = [NSColor colorWithRed:0.035 green:0.055 blue:0.065 alpha:1.0].CGColor;
    ltcPanel.layer.cornerRadius = 10.0;
    ltcPanel.layer.borderWidth = 1.0;
    ltcPanel.layer.borderColor = [NSColor colorWithRed:0.24 green:0.62 blue:0.42 alpha:0.75].CGColor;
    [monitorPanel addSubview:ltcPanel];
    NSTextField *ltcTitle = [self label:@"LTC TIMECODE" frame:NSMakeRect(12, 42, 220, 14) size:8 bold:YES];
    ltcTitle.alignment = NSTextAlignmentCenter;
    ltcTitle.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
    [ltcPanel addSubview:ltcTitle];
    self.ltcTimecode = [self label:@"--:--:--:--" frame:NSMakeRect(12, 10, 220, 30) size:18 bold:YES];
    self.ltcTimecode.alignment = NSTextAlignmentCenter;
    self.ltcTimecode.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightBold];
    self.ltcTimecode.textColor = [NSColor colorWithWhite:0.58 alpha:1.0];
    [ltcPanel addSubview:self.ltcTimecode];

    NSTextField *monitorFooter = [self label:@"Écoute native CoreMIDI · hors de Live" frame:NSMakeRect(18, 30, 240, 18) size:9 bold:YES];
    monitorFooter.alignment = NSTextAlignmentCenter;
    monitorFooter.textColor = [NSColor colorWithWhite:0.42 alpha:1.0];
    [monitorPanel addSubview:monitorFooter];

    [self setupReturnMonitor];
    [self setupSceneContextListener];
    [self refreshEndpoints];
    self.discoveredPeers = [NSMutableOrderedSet orderedSet];
    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.serviceBrowser.delegate = self;
    [self.serviceBrowser searchForServicesOfType:@"_apple-midi._udp." inDomain:@"local."];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshTimer:) userInfo:nil repeats:YES];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(refreshPublishedStatus:) userInfo:nil repeats:YES];
    [self refreshPublishedStatus:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshPublishedStatus:(NSTimer *)timer {
    (void)timer;
    if (self.statusRequestRunning) return;
    self.statusRequestRunning = YES;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:5050/status"]];
    request.timeoutInterval = 0.5;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        NSString *timecode = nil;
        BOOL connected = NO;
        if (data.length && !error) {
            NSDictionary *status = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            connected = [status[@"ltc_connected"] boolValue];
            NSString *candidate = [status[@"ltc_timecode"] isKindOfClass:NSString.class] ? status[@"ltc_timecode"] : nil;
            if (connected && candidate.length == 11) timecode = candidate;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusRequestRunning = NO;
            NSString *display = timecode ?: @"--:--:--:--";
            NSColor *color = timecode
                ? [NSColor colorWithRed:0.35 green:0.95 blue:0.58 alpha:1.0]
                : [NSColor colorWithWhite:0.58 alpha:1.0];
            self.ltcTimecode.stringValue = display;
            self.ltcTimecode.textColor = color;
        });
    }] resume];
}

- (void)setupSceneContextListener {
    self.sceneSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (self.sceneSocket < 0) return;
    int reuse = 1;
    setsockopt(self.sceneSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    fcntl(self.sceneSocket, F_SETFL, O_NONBLOCK);
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(CLSceneContextPort);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(self.sceneSocket, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(self.sceneSocket);
        self.sceneSocket = -1;
        return;
    }
    self.sceneSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)self.sceneSocket, 0,
                                               dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.sceneSource, ^{
        UInt8 buffer[4096];
        ssize_t count = 0;
        while ((count = recv(weakSelf.sceneSocket, buffer, sizeof(buffer), 0)) > 0) {
            NSData *packet = [NSData dataWithBytes:buffer length:(NSUInteger)count];
            [weakSelf handleSceneDatagram:packet];
        }
    });
    dispatch_resume(self.sceneSource);
}

- (void)handleSceneDatagram:(NSData *)data {
    NSUInteger offset = 0;
    NSString *address = CLReadOSCString(data, &offset);
    NSString *types = CLReadOSCString(data, &offset);
    if (![address isEqualToString:@"/cl/midi-monitor/scene"] || ![types hasPrefix:@","]) return;
    NSString *sceneName = nil;
    const UInt8 *bytes = data.bytes;
    for (NSUInteger index = 1; index < types.length; index++) {
        unichar type = [types characterAtIndex:index];
        if (type == 'i' || type == 'f') {
            if (offset + 4 > data.length) return;
            offset += 4;
        } else if (type == 's') {
            sceneName = CLReadOSCString(data, &offset);
            if (!sceneName) return;
        }
    }
    if (!sceneName.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.currentSceneName = sceneName;
    });
}

- (void)setupReturnMonitor {
    self.pendingCL5Program = -1;
    self.pendingQL1Program = -1;
    self.lastCL5Program = -1;
    self.lastQL1Program = -1;
    [self writePublishedConsoleState];
    OSStatus clientStatus = MIDIClientCreate(CFSTR("CL Console Return Monitor"), NULL, NULL, &_monitorClient);
    OSStatus portStatus = clientStatus == noErr
        ? MIDIInputPortCreate(self.monitorClient, CFSTR("Console returns"), CLReturnMonitorRead,
                              (__bridge void *)self, &_monitorInputPort)
        : clientStatus;
    if (clientStatus != noErr || portStatus != noErr) {
        self.monitorStatus.stringValue = @"Écoute CoreMIDI indisponible";
        self.monitorStatus.textColor = NSColor.systemRedColor;
    }
}

- (void)writePublishedConsoleState {
    NSDictionary *payload = @{
        @"service": @"cl-midi-console-monitor",
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
        @"cl5": @{
            @"program": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"title": self.cl5Scene.stringValue ?: @"",
            @"received": @(self.lastCL5Program >= 0),
        },
        @"ql1": @{
            @"program": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"title": self.ql1Scene.stringValue ?: @"",
            @"received": @(self.lastQL1Program >= 0),
        },
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [data writeToFile:@"/private/tmp/CL_MIDI_Console_State.json" options:NSDataWritingAtomic error:nil];
}

- (void)queueProgram:(UInt8)program channel:(UInt8)channel {
    if (channel != 1 && channel != 2) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (self) {
        if (channel == 1) {
            if (self.lastCL5Program == program && now - self.lastCL5ProgramAt < 1.0) return;
            self.lastCL5Program = program;
            self.lastCL5ProgramAt = now;
            self.pendingCL5Program = program;
        } else {
            if (self.lastQL1Program == program && now - self.lastQL1ProgramAt < 1.0) return;
            self.lastQL1Program = program;
            self.lastQL1ProgramAt = now;
            self.pendingQL1Program = program;
        }
        if (self.returnUpdateScheduled) return;
        self.returnUpdateScheduled = YES;
    }

    // Never enqueue one AppKit update per MIDI packet. A network feedback storm
    // must not be able to starve the application's main event loop.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSInteger cl5 = -1;
        NSInteger ql1 = -1;
        @synchronized (self) {
            cl5 = self.pendingCL5Program;
            ql1 = self.pendingQL1Program;
            self.pendingCL5Program = -1;
            self.pendingQL1Program = -1;
            self.returnUpdateScheduled = NO;
        }
        if (cl5 >= 0) [self handleProgram:(UInt8)cl5 channel:1];
        if (ql1 >= 0) [self handleProgram:(UInt8)ql1 channel:2];
    });
}

- (void)selectReturnMonitorSourceNamed:(NSString *)name {
    MIDIEndpointRef selectedSource = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) {
        MIDIEndpointRef source = MIDIGetSource(index);
        if ([EndpointName(source) isEqualToString:name]) {
            selectedSource = source;
            break;
        }
    }
    if (selectedSource == self.monitorSource) return;
    if (self.monitorSource && self.monitorInputPort) {
        MIDIPortDisconnectSource(self.monitorInputPort, self.monitorSource);
    }
    self.monitorSource = 0;
    if (!selectedSource || !self.monitorInputPort) {
        self.monitorStatus.stringValue = @"Aucune entrée RTP sélectionnée";
        self.monitorStatus.textColor = NSColor.systemOrangeColor;
        return;
    }
    OSStatus status = MIDIPortConnectSource(self.monitorInputPort, selectedSource, NULL);
    if (status == noErr) {
        self.monitorSource = selectedSource;
        self.monitorStatus.stringValue = [NSString stringWithFormat:@"Écoute active sur %@", name];
        self.monitorStatus.textColor = NSColor.systemGreenColor;
    } else {
        self.monitorStatus.stringValue = [NSString stringWithFormat:@"Impossible d’écouter %@", name];
        self.monitorStatus.textColor = NSColor.systemRedColor;
    }
}

- (void)handleProgram:(UInt8)program channel:(UInt8)channel {
    NSInteger displayedProgram = (NSInteger)program + 1;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    NSString *detail = [NSString stringWithFormat:@"✓ RETOUR REÇU · %@", [formatter stringFromDate:NSDate.date]];
    if (channel == 1) {
        self.cl5Program.stringValue = [NSString stringWithFormat:@"CL5 · N° %ld", (long)displayedProgram];
        self.cl5Detail.stringValue = detail;
        self.cl5Detail.textColor = NSColor.systemGreenColor;
        self.cl5Scene.stringValue = self.currentSceneName.length ? self.currentSceneName : @"Titre non reçu";
        [self writePublishedConsoleState];
    } else if (channel == 2) {
        self.ql1Program.stringValue = [NSString stringWithFormat:@"QL1 · N° %ld", (long)displayedProgram];
        self.ql1Detail.stringValue = detail;
        self.ql1Detail.textColor = NSColor.systemGreenColor;
        self.ql1Scene.stringValue = self.currentSceneName.length ? self.currentSceneName : @"Titre non reçu";
        [self writePublishedConsoleState];
    }
}

- (void)setLamp:(NSColor *)color title:(NSString *)title detail:(NSString *)detail {
    self.lamp.layer.backgroundColor = color.CGColor;
    self.lamp.layer.shadowColor = color.CGColor;
    self.lamp.layer.shadowOpacity = 0.75;
    self.lamp.layer.shadowRadius = 8;
    self.headline.stringValue = title;
    self.detail.stringValue = detail;
}

- (void)refreshTimer:(NSTimer *)timer { (void)timer; [self refreshEndpoints]; }
- (void)refreshNow:(id)sender { (void)sender; [self refreshEndpoints]; [self inspectMidiDirectory]; }
- (void)endpointChanged:(id)sender { (void)sender; self.validatedEndpoint = nil; [self refreshEndpoints]; }
- (void)targetChanged:(id)sender {
    (void)sender;
    NSString *target = self.targetMenu.selectedItem.title;
    if (target.length && ![target hasPrefix:@"Recherche"] && ![target hasPrefix:@"Aucun"]) {
        [[NSUserDefaults standardUserDefaults] setObject:target forKey:@"preferredRtpPeer"];
    }
}

- (void)refreshTargetMenu {
    NSString *selected = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    NSMutableArray<NSString *> *available = [self.discoveredPeers.array mutableCopy];
    if (self.localNetworkName.length) [available removeObject:self.localNetworkName];
    if (selected.length && ![available containsObject:selected]) [available addObject:selected];
    NSArray<NSString *> *names = [available sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.targetMenu removeAllItems];
    [self.targetMenu addItemsWithTitles:names.count ? names : @[@"Aucun correspondant découvert"]];
    if (selected.length && [names containsObject:selected]) [self.targetMenu selectItemWithTitle:selected];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    self.connectButton.enabled = names.count > 0;
}

- (void)inspectMidiDirectory {
    if (self.peerInspectionRunning) return;
    self.peerInspectionRunning = YES;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[[self toolPath:@"list_rtp_peers.applescript"]];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.peerInspectionRunning = NO;
            if (finished.terminationStatus != 0) return;
            for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if ([line hasPrefix:@"SELF\t"]) self.localNetworkName = [line substringFromIndex:5];
                if ([line hasPrefix:@"PEER\t"]) [self.discoveredPeers addObject:[line substringFromIndex:5]];
            }
            [self refreshTargetMenu];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) self.peerInspectionRunning = NO;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length) [self.discoveredPeers addObject:service.name];
    if (!moreComing) [self refreshTargetMenu];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length) [self.discoveredPeers removeObject:service.name];
    if (!moreComing) [self refreshTargetMenu];
}

- (void)connectSelectedPeer:(id)sender {
    (void)sender;
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    if (!peer.length || [peer hasPrefix:@"Aucun"] || [peer hasPrefix:@"Recherche"]) return;
    [[NSUserDefaults standardUserDefaults] setObject:peer forKey:@"preferredRtpPeer"];
    self.connectButton.enabled = NO;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion RTP vers %@…", peer];
    NSString *helper = [NSString stringWithContentsOfFile:[self toolPath:@"connect_rtp_peer.applescript"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *escapedPeer = [[peer stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                              stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *source = [helper stringByReplacingOccurrencesOfString:@"__CL_PEER__" withString:escapedPeer];
    NSDictionary *scriptError = nil;
    NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&scriptError];
    NSString *output = result.stringValue ?: @"";
    self.connectButton.enabled = YES;
    if (scriptError == nil && [output rangeOfString:@"already-connected:"].location != NSNotFound) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"%@ est déjà connecté · test MIDI requis", peer];
    } else if (scriptError == nil && [output rangeOfString:@"connected:"].location != NSNotFound) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion RTP établie avec %@ · test MIDI requis", peer];
    } else {
        NSString *reason = scriptError[NSAppleScriptErrorMessage] ?: @"erreur inconnue";
        self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion impossible : %@", reason];
    }
}

- (void)refreshEndpoints {
    NSArray<NSString *> *sources = EndpointNames(YES);
    NSArray<NSString *> *destinations = EndpointNames(NO);
    NSString *selected = self.endpointMenu.selectedItem.title;
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    for (NSString *name in sources) {
        if ([name rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound) [candidates addObject:name];
    }
    for (NSString *name in destinations) {
        if ([name rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound) [candidates addObject:name];
    }
    [self.endpointMenu removeAllItems];
    [self.endpointMenu addItemsWithTitles:candidates.array.count ? candidates.array : @[@"Aucun port RTP détecté"]];
    if (selected.length && [candidates containsObject:selected]) [self.endpointMenu selectItemWithTitle:selected];
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];

    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    [self selectReturnMonitorSourceNamed:endpoint];
    BOOL hasSource = [sources containsObject:endpoint];
    BOOL hasDestination = [destinations containsObject:endpoint];
    MIDINetworkSession *session = [MIDINetworkSession defaultSession];
    self.sessionInfo.stringValue = [NSString stringWithFormat:@"Session API : %@ · port %lu · connexions déclarées : %lu\nEntrée : %@ · sortie : %@",
        session.isEnabled ? @"active" : @"indisponible", (unsigned long)session.networkPort,
        (unsigned long)session.connections.count, hasSource ? @"visible" : @"absente", hasDestination ? @"visible" : @"absente"];

    if (self.validatedEndpoint && [self.validatedEndpoint isEqualToString:endpoint]) {
        NSTimeInterval age = -[self.validatedAt timeIntervalSinceNow];
        [self setLamp:[NSColor systemGreenColor] title:@"RTP VALIDÉ" detail:[NSString stringWithFormat:@"Aller-retour confirmé il y a %.0f s sur %@", age, endpoint]];
    } else if (hasSource && hasDestination) {
        [self setLamp:[NSColor systemOrangeColor] title:@"RTP DISPONIBLE" detail:@"Le port est visible ; lancez un test pour valider le retour réel."];
    } else {
        [self setLamp:[NSColor systemRedColor] title:@"RTP HORS LIGNE" detail:@"Aucune paire entrée/sortie RTP exploitable n’est visible."];
    }
}

- (NSString *)toolPath:(NSString *)name {
    return [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:[@"Network Tools" stringByAppendingPathComponent:name]];
}

- (void)runTest:(id)sender {
    (void)sender;
    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    NSInteger program = self.programField.integerValue;
    NSInteger channel = self.testTargetMenu.indexOfSelectedItem + 1;
    NSString *console = channel == 2 ? @"QL1" : @"CL5";
    if ([endpoint hasPrefix:@"Aucun"] || program < 1 || program > 128) {
        self.lastTest.stringValue = @"Sélection ou Program Change invalide";
        return;
    }
    self.testButton.enabled = NO;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Test %@ · canal %ld · PGM %ld…", console, (long)channel, (long)program];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLMIDIRoundTripTester"]];
    task.arguments = @[@"--endpoint", endpoint,
                       @"--program", [NSString stringWithFormat:@"%ld", (long)program],
                       @"--channel", [NSString stringWithFormat:@"%ld", (long)channel],
                       @"--timeout", @"5"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            if (finished.terminationStatus == 0) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"latency_ms=([0-9.]+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
                NSString *latency = match ? [output substringWithRange:[match rangeAtIndex:1]] : @"?";
                self.validatedEndpoint = endpoint;
                self.validatedAt = [NSDate date];
                self.lastTest.stringValue = [NSString stringWithFormat:@"✓ %@ · canal %ld · PGM %ld confirmé · %@ ms", console, (long)channel, (long)program, latency];
            } else {
                self.validatedEndpoint = nil;
                NSString *reason = [output rangeOfString:@"TIMEOUT"].location != NSNotFound ? @"aucun retour reçu" : @"test impossible";
                self.lastTest.stringValue = [NSString stringWithFormat:@"Échec : %@", reason];
            }
            [self refreshEndpoints];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.testButton.enabled = YES;
        self.lastTest.stringValue = [NSString stringWithFormat:@"Impossible de lancer le test : %@", error.localizedDescription];
    }
}

- (void)openMidiSetup:(id)sender {
    (void)sender;
    NSString *source = [NSString stringWithContentsOfFile:[self toolPath:@"open_rtp_settings.applescript"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (error) self.lastTest.stringValue = @"Impossible d’ouvrir directement les réglages RTP. Vérifiez l’autorisation Accessibilité.";
    else [self inspectMidiDirectory];
}

- (void)startSimulator:(id)sender {
    (void)sender;
    if (self.simulatorDashboardTask.running) {
        [[NSRunningApplication runningApplicationWithProcessIdentifier:self.simulatorDashboardTask.processIdentifier]
            activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        return;
    }
    NSString *tool = [self toolPath:@"CLYamahaSimulatorDashboard"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:tool]) {
        self.lastTest.stringValue = @"Console Simulator introuvable dans l’application.";
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.simulatorDashboardTask == finished) weakSelf.simulatorDashboardTask = nil;
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"Impossible d’ouvrir Console Simulator : %@", error.localizedDescription ?: @"erreur inconnue"];
        return;
    }
    self.simulatorDashboardTask = task;
    self.lastTest.stringValue = @"Console Simulator ouvert.";
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (self.monitorSource && self.monitorInputPort) MIDIPortDisconnectSource(self.monitorInputPort, self.monitorSource);
    [self.statusTimer invalidate];
    if (self.monitorInputPort) MIDIPortDispose(self.monitorInputPort);
    if (self.monitorClient) MIDIClientDispose(self.monitorClient);
    if (self.sceneSource) dispatch_source_cancel(self.sceneSource);
    if (self.sceneSocket >= 0) close(self.sceneSocket);
    return NSTerminateNow;
}
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        CLNetworkDelegate *delegate = [[CLNetworkDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}

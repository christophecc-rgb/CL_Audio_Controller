#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <sys/socket.h>
#import <unistd.h>

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

@interface CLNetworkDelegate : NSObject <NSApplicationDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property NSWindow *window;
@property NSView *headerPanel;
@property NSView *statusPanel;
@property NSView *targetPanel;
@property NSView *testPanel;
@property NSView *technicalPanel;
@property NSTextField *appTitleLabel;
@property NSTextField *appSubtitleLabel;
@property NSTextField *compactSummary;
@property NSTextField *footerLabel;
@property NSButton *showModeButton;
@property NSButton *settingsButton;
@property NSButton *refreshButton;
@property NSButton *simulatorButton;
@property BOOL showModeEnabled;
@property NSString *lastCL5Test;
@property NSString *lastQL1Test;
@property NSView *lamp;
@property NSTextField *headline;
@property NSTextField *detail;
@property NSTextField *lastTest;
@property NSPopUpButton *endpointMenu;
@property NSTextField *programField;
@property NSPopUpButton *testTargetMenu;
@property NSButton *testButton;
@property NSPopUpButton *targetMenu;
@property NSButton *connectButton;
@property NSTimer *timer;
@property NSNetServiceBrowser *serviceBrowser;
@property NSMutableOrderedSet<NSString *> *discoveredPeers;
@property NSMutableDictionary<NSString *, NSNetService *> *peerServices;
@property NSMutableDictionary<NSString *, NSString *> *peerHosts;
@property BOOL remoteSimulatorRunning;
@property NSString *localNetworkName;
@property BOOL peerInspectionRunning;
@property NSString *validatedEndpoint;
@property NSDate *validatedAt;
@property NSString *loopDetectedEndpoint;
@property NSTask *simulatorDashboardTask;
@property NSTask *guardianTask;
@property NSString *guardianPeer;
@property NSTask *legacyWakeTask;
@property BOOL legacyWakeRunning;
@property BOOL legacyWakeCompleted;
@property NSTextField *technicalSession;
@property NSTextField *technicalEndpoints;
@property NSTextField *technicalPeers;
@property NSTextField *technicalSelection;
@property MIDIClientRef returnMonitorClient;
@property MIDIPortRef returnMonitorInputPort;
@property MIDIEndpointRef returnMonitorSource;
@property NSInteger pendingCL5Program;
@property NSInteger pendingQL1Program;
@property NSInteger lastCL5Program;
@property NSInteger lastQL1Program;
@property NSDate *lastCL5ProgramAt;
@property NSDate *lastQL1ProgramAt;
@property BOOL returnUpdateScheduled;
- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel;
@end

static void CLPassiveReturnRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)srcConnRefCon;
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 status = packet->data[index];
            if ((status & 0xF0) == 0xC0 && index + 1 < packet->length) {
                [delegate queueReturnedProgram:packet->data[index + 1] channel:(status & 0x0F) + 1];
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
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 900)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI Network Assistant";
    self.lastCL5Test = @"non testé";
    self.lastQL1Test = @"non testé";
    self.pendingCL5Program = -1;
    self.pendingQL1Program = -1;
    self.lastCL5Program = -1;
    self.lastQL1Program = -1;
    self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.045 blue:0.060 alpha:1.0];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSView *content = self.window.contentView;

    NSView *header = self.headerPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 796, 468, 88)];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.023 blue:0.032 alpha:1.0].CGColor;
    header.layer.cornerRadius = 12.0;
    header.layer.borderWidth = 1.0;
    header.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor;
    [content addSubview:header];

    NSString *logoPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"paradis_latin_logo.jpg"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    NSImageView *logoView = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 8, 444, 72)];
    logoView.image = logo;
    logoView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [header addSubview:logoView];
    NSTextField *appTitle = self.appTitleLabel = [self label:@"CL MIDI NETWORK ASSISTANT" frame:NSMakeRect(20, 744, 270, 24) size:15 bold:YES];
    NSTextField *appSubtitle = self.appSubtitleLabel = [self label:@"Technique RTP · CoreMIDI" frame:NSMakeRect(286, 746, 94, 20) size:9 bold:NO];
    appSubtitle.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
    NSShadow *silverShadow = [[NSShadow alloc] init];
    silverShadow.shadowColor = [NSColor colorWithWhite:1.0 alpha:0.22];
    silverShadow.shadowOffset = NSMakeSize(0, -1);
    silverShadow.shadowBlurRadius = 1.0;
    appTitle.attributedStringValue = [[NSAttributedString alloc] initWithString:@"CL MIDI NETWORK ASSISTANT" attributes:@{
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.76 green:0.79 blue:0.84 alpha:1.0],
        NSFontAttributeName: [NSFont boldSystemFontOfSize:15.0],
        NSShadowAttributeName: silverShadow
    }];
    [content addSubview:appTitle];
    [content addSubview:appSubtitle];
    self.showModeButton = [self accentButton:@"Mode spectacle" frame:NSMakeRect(384, 741, 100, 30) action:@selector(toggleShowMode:) color:[NSColor colorWithRed:0.24 green:0.28 blue:0.35 alpha:1.0]];
    [content addSubview:self.showModeButton];

    NSView *statusPanel = self.statusPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 651, 468, 84)];
    statusPanel.wantsLayer = YES; statusPanel.layer.cornerRadius = 12; statusPanel.layer.borderWidth = 1;
    statusPanel.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.075 blue:0.095 alpha:1.0].CGColor;
    statusPanel.layer.borderColor = [NSColor colorWithRed:0.22 green:0.55 blue:0.78 alpha:0.7].CGColor;
    [content addSubview:statusPanel];
    self.lamp = [[NSView alloc] initWithFrame:NSMakeRect(18, 27, 22, 22)];
    self.lamp.wantsLayer = YES;
    self.lamp.layer.cornerRadius = 11;
    [statusPanel addSubview:self.lamp];
    self.headline = [self label:@"Analyse de la connexion RTP…" frame:NSMakeRect(54, 43, 394, 25) size:17 bold:YES];
    self.detail = [self label:@"" frame:NSMakeRect(54, 17, 394, 22) size:11 bold:NO];
    [statusPanel addSubview:self.headline]; [statusPanel addSubview:self.detail];

    NSView *targetPanel = self.targetPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 543, 468, 100)];
    targetPanel.wantsLayer = YES; targetPanel.layer.cornerRadius = 12; targetPanel.layer.borderWidth = 1;
    targetPanel.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.088 blue:0.11 alpha:1.0].CGColor;
    targetPanel.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor; [content addSubview:targetPanel];
    [targetPanel addSubview:[self label:@"CONNEXION À LA CIBLE RTP" frame:NSMakeRect(16, 68, 220, 20) size:10 bold:YES]];
    self.targetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 24, 308, 34) pullsDown:NO];
    self.targetMenu.target = self;
    self.targetMenu.action = @selector(targetChanged:);
    [self.targetMenu addItemWithTitle:@"Recherche des correspondants…"];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    [targetPanel addSubview:self.targetMenu];
    self.connectButton = [self accentButton:@"Connecter" frame:NSMakeRect(334, 23, 118, 36) action:@selector(connectSelectedPeer:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.82 alpha:1.0]];
    [targetPanel addSubview:self.connectButton];

    NSView *testPanel = self.testPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 390, 468, 145)];
    testPanel.wantsLayer = YES; testPanel.layer.cornerRadius = 12; testPanel.layer.borderWidth = 1;
    testPanel.layer.backgroundColor = [NSColor colorWithRed:0.065 green:0.073 blue:0.09 alpha:1.0].CGColor;
    testPanel.layer.borderColor = [NSColor colorWithRed:0.38 green:0.30 blue:0.65 alpha:0.7].CGColor; [content addSubview:testPanel];
    [testPanel addSubview:[self label:@"TEST ALLER-RETOUR MIDI" frame:NSMakeRect(16, 115, 190, 20) size:10 bold:YES]];
    self.endpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 76, 194, 32) pullsDown:NO];
    self.endpointMenu.target = self;
    self.endpointMenu.action = @selector(endpointChanged:);
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];
    [testPanel addSubview:self.endpointMenu];
    self.testTargetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(218, 76, 108, 32) pullsDown:NO];
    [self.testTargetMenu addItemsWithTitles:@[@"CL5 · Ch.1", @"QL1 · Ch.2"]];
    [self stylePopup:self.testTargetMenu accent:[NSColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:1.0]];
    [testPanel addSubview:self.testTargetMenu];
    self.programField = [[NSTextField alloc] initWithFrame:NSMakeRect(334, 76, 52, 32)];
    self.programField.stringValue = @"42";
    self.programField.alignment = NSTextAlignmentCenter;
    self.programField.font = [NSFont boldSystemFontOfSize:14.0];
    self.programField.textColor = [NSColor colorWithRed:0.55 green:0.90 blue:0.68 alpha:1.0];
    self.programField.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0];
    [testPanel addSubview:self.programField];
    self.testButton = [self accentButton:@"Tester" frame:NSMakeRect(394, 75, 58, 34) action:@selector(runTest:) color:[NSColor colorWithRed:0.08 green:0.58 blue:0.32 alpha:1.0]];
    [testPanel addSubview:self.testButton];

    self.lastTest = [self label:@"Aucun aller-retour validé" frame:NSMakeRect(16, 18, 436, 36) size:11 bold:YES];
    self.lastTest.maximumNumberOfLines = 2;
    [testPanel addSubview:self.lastTest];

    NSView *technicalPanel = self.technicalPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 132, 468, 250)];
    technicalPanel.wantsLayer = YES;
    technicalPanel.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.027 blue:0.038 alpha:1.0].CGColor;
    technicalPanel.layer.cornerRadius = 12.0;
    technicalPanel.layer.borderWidth = 1.0;
    technicalPanel.layer.borderColor = [NSColor colorWithRed:0.20 green:0.44 blue:0.60 alpha:0.75].CGColor;
    [content addSubview:technicalPanel];

    NSTextField *technicalTitle = [self label:@"DIAGNOSTIC RÉSEAU MIDI" frame:NSMakeRect(16, 216, 250, 24) size:13 bold:YES];
    technicalTitle.textColor = [NSColor colorWithRed:0.40 green:0.78 blue:1.0 alpha:1.0];
    [technicalPanel addSubview:technicalTitle];
    NSTextField *technicalSubtitle = [self label:@"Actualisation automatique toutes les 2 secondes" frame:NSMakeRect(252, 218, 200, 18) size:8 bold:NO];
    technicalSubtitle.alignment = NSTextAlignmentRight;
    [technicalPanel addSubview:technicalSubtitle];

    [technicalPanel addSubview:[self label:@"SESSION RTP OBSERVÉE" frame:NSMakeRect(16, 186, 160, 18) size:9 bold:YES]];
    self.technicalSession = [self label:@"Analyse…" frame:NSMakeRect(16, 140, 208, 44) size:10 bold:NO];
    self.technicalSession.maximumNumberOfLines = 3;
    [technicalPanel addSubview:self.technicalSession];

    NSTextField *systemSettingsNotice = [self label:@"Activation et autorisations gérées dans Réglages de réseau MIDI macOS" frame:NSMakeRect(16, 36, 436, 34) size:10 bold:NO];
    systemSettingsNotice.alignment = NSTextAlignmentCenter;
    systemSettingsNotice.textColor = [NSColor colorWithRed:0.55 green:0.70 blue:0.86 alpha:1.0];
    [technicalPanel addSubview:systemSettingsNotice];

    [technicalPanel addSubview:[self label:@"PORTS COREMIDI" frame:NSMakeRect(236, 186, 150, 18) size:9 bold:YES]];
    self.technicalEndpoints = [self label:@"Analyse…" frame:NSMakeRect(236, 140, 216, 44) size:10 bold:NO];
    self.technicalEndpoints.maximumNumberOfLines = 4;
    [technicalPanel addSubview:self.technicalEndpoints];

    [technicalPanel addSubview:[self label:@"PORT SÉLECTIONNÉ" frame:NSMakeRect(16, 112, 150, 18) size:9 bold:YES]];
    self.technicalSelection = [self label:@"Aucun" frame:NSMakeRect(16, 74, 208, 36) size:10 bold:NO];
    self.technicalSelection.maximumNumberOfLines = 2;
    [technicalPanel addSubview:self.technicalSelection];

    [technicalPanel addSubview:[self label:@"CORRESPONDANTS BONJOUR" frame:NSMakeRect(236, 112, 190, 18) size:9 bold:YES]];
    self.technicalPeers = [self label:@"Recherche…" frame:NSMakeRect(236, 74, 216, 36) size:10 bold:NO];
    self.technicalPeers.maximumNumberOfLines = 3;
    [technicalPanel addSubview:self.technicalPeers];

    self.settingsButton = [self accentButton:@"Réglages réseau MIDI" frame:NSMakeRect(16, 88, 228, 36) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.27 green:0.36 blue:0.49 alpha:1.0]]; [content addSubview:self.settingsButton];
    self.refreshButton = [self accentButton:@"Actualiser le diagnostic" frame:NSMakeRect(256, 88, 228, 36) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.30 green:0.35 blue:0.43 alpha:1.0]]; [content addSubview:self.refreshButton];
    self.simulatorButton = [self accentButton:@"DÉMARRER LE SIMULATEUR DISTANT" frame:NSMakeRect(16, 38, 468, 42) action:@selector(startSimulator:) color:[NSColor colorWithRed:0.55 green:0.39 blue:0.28 alpha:1.0]]; [content addSubview:self.simulatorButton];
    NSTextField *footer = self.footerLabel = [self label:@"CL AUDIO · MIDI NETWORK · 2026" frame:NSMakeRect(16, 10, 468, 18) size:8 bold:YES];
    footer.alignment = NSTextAlignmentCenter; footer.textColor = [NSColor colorWithWhite:0.38 alpha:1.0]; [content addSubview:footer];
    self.compactSummary = [self label:@"Aucun test aller-retour validé" frame:NSMakeRect(24, 66, 452, 54) size:12 bold:YES];
    self.compactSummary.maximumNumberOfLines = 3; self.compactSummary.hidden = YES; [content addSubview:self.compactSummary];

    [self refreshEndpoints];
    self.discoveredPeers = [NSMutableOrderedSet orderedSet];
    self.peerServices = [NSMutableDictionary dictionary];
    self.peerHosts = [NSMutableDictionary dictionary];
    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.serviceBrowser.delegate = self;
    [self.serviceBrowser searchForServicesOfType:@"_apple-midi._udp." inDomain:@"local."];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshTimer:) userInfo:nil repeats:YES];
    [self ensureGuardianRunning];
    [self ensureLegacyWakeIfNeeded];
    [self setupPassiveReturnMonitor];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)writeConsoleReturnState {
    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    NSDictionary *payload = @{
        @"service": @"cl-midi-console-monitor",
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
        @"rtp": @{
            @"peer": peer,
            @"endpoint": endpoint,
            @"available": @(![endpoint hasPrefix:@"Aucun"] && endpoint.length > 0),
            @"validated": @(self.validatedEndpoint && [self.validatedEndpoint isEqualToString:endpoint]),
            @"loop_detected": @(self.loopDetectedEndpoint && [self.loopDetectedEndpoint isEqualToString:endpoint]),
            @"last_test": self.lastTest.stringValue ?: @"",
        },
        @"cl5": @{
            @"program": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"title": @"",
            @"received": @(self.lastCL5Program >= 0),
            @"received_at": self.lastCL5ProgramAt ? @([self.lastCL5ProgramAt timeIntervalSince1970]) : NSNull.null,
        },
        @"ql1": @{
            @"program": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"title": @"",
            @"received": @(self.lastQL1Program >= 0),
            @"received_at": self.lastQL1ProgramAt ? @([self.lastQL1ProgramAt timeIntervalSince1970]) : NSNull.null,
        },
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [data writeToFile:@"/private/tmp/CL_MIDI_Console_State.json" options:NSDataWritingAtomic error:nil];
}

- (void)setupPassiveReturnMonitor {
    OSStatus clientStatus = MIDIClientCreate(CFSTR("CL Passive Console Return Monitor"), NULL, NULL, &_returnMonitorClient);
    OSStatus portStatus = clientStatus == noErr
        ? MIDIInputPortCreate(self.returnMonitorClient, CFSTR("Console return input"), CLPassiveReturnRead,
                              (__bridge void *)self, &_returnMonitorInputPort)
        : clientStatus;
    if (clientStatus != noErr || portStatus != noErr) {
        self.lastTest.stringValue = @"Écoute passive des retours consoles indisponible";
    }
    [self writeConsoleReturnState];
    [self selectPassiveReturnSourceNamed:self.endpointMenu.selectedItem.title ?: @""];
}

- (void)selectPassiveReturnSourceNamed:(NSString *)name {
    MIDIEndpointRef selectedSource = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) {
        MIDIEndpointRef source = MIDIGetSource(index);
        if ([EndpointName(source) isEqualToString:name]) {
            selectedSource = source;
            break;
        }
    }
    if (selectedSource == self.returnMonitorSource) return;
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
    }
    self.returnMonitorSource = 0;
    if (selectedSource && self.returnMonitorInputPort &&
        MIDIPortConnectSource(self.returnMonitorInputPort, selectedSource, NULL) == noErr) {
        self.returnMonitorSource = selectedSource;
    }
}

- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel {
    if (channel != 1 && channel != 2) return;
    @synchronized (self) {
        if (channel == 1) self.pendingCL5Program = program;
        else self.pendingQL1Program = program;
        if (self.returnUpdateScheduled) return;
        self.returnUpdateScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        @synchronized (self) {
            if (self.pendingCL5Program >= 0) {
                self.lastCL5Program = self.pendingCL5Program;
                self.lastCL5ProgramAt = [NSDate date];
            }
            if (self.pendingQL1Program >= 0) {
                self.lastQL1Program = self.pendingQL1Program;
                self.lastQL1ProgramAt = [NSDate date];
            }
            self.pendingCL5Program = -1;
            self.pendingQL1Program = -1;
            self.returnUpdateScheduled = NO;
        }
        [self writeConsoleReturnState];
    });
}

- (void)updateCompactSummary {
    NSString *peers = self.technicalPeers.stringValue.length ? self.technicalPeers.stringValue : @"Aucun réseau détecté";
    peers = [peers stringByReplacingOccurrencesOfString:@"\n" withString:@" · "];
    self.compactSummary.stringValue = [NSString stringWithFormat:@"RÉSEAUX CONSOLES · %@\nCL5 · %@\nQL1 · %@",
        peers, self.lastCL5Test ?: @"non testé", self.lastQL1Test ?: @"non testé"];
}

- (void)toggleShowMode:(id)sender {
    (void)sender;
    self.showModeEnabled = !self.showModeEnabled;
    [self updateCompactSummary];
    self.targetPanel.hidden = self.showModeEnabled;
    self.testPanel.hidden = self.showModeEnabled;
    self.technicalPanel.hidden = self.showModeEnabled;
    self.settingsButton.hidden = self.showModeEnabled;
    self.refreshButton.hidden = self.showModeEnabled;
    self.simulatorButton.hidden = self.showModeEnabled;
    self.compactSummary.hidden = !self.showModeEnabled;
    self.showModeButton.title = self.showModeEnabled ? @"Panneau complet" : @"Mode spectacle";
    if (self.showModeEnabled) {
        [self.window setContentSize:NSMakeSize(500, 430)];
        self.headerPanel.frame = NSMakeRect(16, 326, 468, 88);
        self.appTitleLabel.frame = NSMakeRect(20, 286, 270, 24);
        self.appSubtitleLabel.frame = NSMakeRect(286, 288, 94, 20);
        self.showModeButton.frame = NSMakeRect(384, 283, 100, 30);
        self.statusPanel.frame = NSMakeRect(16, 190, 468, 84);
        self.compactSummary.frame = NSMakeRect(24, 104, 452, 62);
        self.footerLabel.frame = NSMakeRect(16, 18, 468, 18);
    } else {
        [self.window setContentSize:NSMakeSize(500, 900)];
        self.headerPanel.frame = NSMakeRect(16, 796, 468, 88);
        self.appTitleLabel.frame = NSMakeRect(20, 744, 270, 24);
        self.appSubtitleLabel.frame = NSMakeRect(286, 746, 94, 20);
        self.showModeButton.frame = NSMakeRect(384, 741, 100, 30);
        self.statusPanel.frame = NSMakeRect(16, 651, 468, 84);
        self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
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

- (void)refreshTimer:(NSTimer *)timer { (void)timer; [self refreshEndpoints]; [self ensureGuardianRunning]; [self ensureLegacyWakeIfNeeded]; }
- (void)refreshNow:(id)sender { (void)sender; self.legacyWakeCompleted = NO; [self refreshEndpoints]; [self inspectMidiDirectory]; [self ensureLegacyWakeIfNeeded]; }
- (void)endpointChanged:(id)sender { (void)sender; self.validatedEndpoint = nil; self.loopDetectedEndpoint = nil; [self refreshEndpoints]; }
- (void)targetChanged:(id)sender {
    (void)sender;
    NSString *target = self.targetMenu.selectedItem.title;
    if (target.length && ![target hasPrefix:@"Recherche"] && ![target hasPrefix:@"Aucun"]) {
        [[NSUserDefaults standardUserDefaults] setObject:target forKey:@"preferredRtpPeer"];
        [self restartGuardianForPeer:target];
    }
}

- (void)startGuardianForPeer:(NSString *)peer {
    if (!peer.length || [peer hasPrefix:@"Aucun"] || [peer hasPrefix:@"Recherche"]) return;
    NSString *tool = [self toolPath:@"CLMIDINetworkGuardian"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:tool]) {
        self.lastTest.stringValue = @"Gardien RTP introuvable dans l’application";
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = @[@"--peer-name", peer, @"--interval", @"2"];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.guardianTask == finished) {
                weakSelf.guardianTask = nil;
                weakSelf.guardianPeer = nil;
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"Gardien RTP non démarré : %@", error.localizedDescription];
        return;
    }
    self.guardianTask = task;
    self.guardianPeer = peer;
}

- (void)restartGuardianForPeer:(NSString *)peer {
    if (self.guardianTask.running) [self.guardianTask terminate];
    self.guardianTask = nil;
    self.guardianPeer = nil;
    [self startGuardianForPeer:peer];
}

- (void)ensureGuardianRunning {
    NSString *peer = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    if (!peer.length) return;
    if (self.guardianTask.running && [self.guardianPeer isEqualToString:peer]) return;
    [self restartGuardianForPeer:peer];
}

- (void)ensureLegacyWakeIfNeeded {
    if (self.legacyWakeRunning || self.legacyWakeCompleted) return;
    NSString *peer = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    if (!peer.length) return;
    NSString *openScript = [self toolPath:@"open_rtp_settings.applescript"];
    NSString *reconnectScript = [self toolPath:@"reconnect_legacy_rtp.applescript"];
    if (![NSFileManager.defaultManager fileExistsAtPath:openScript] ||
        ![NSFileManager.defaultManager fileExistsAtPath:reconnectScript]) return;

    self.legacyWakeRunning = YES;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Réveil de la session RTP historique vers %@…", peer];
    NSTask *openTask = [[NSTask alloc] init];
    openTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    openTask.arguments = @[openScript];
    openTask.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    openTask.standardError = NSFileHandle.fileHandleWithNullDevice;
    self.legacyWakeTask = openTask;
    __weak typeof(self) weakSelf = self;
    openTask.terminationHandler = ^(NSTask *finished) {
        if (finished.terminationStatus != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.legacyWakeRunning = NO;
                weakSelf.legacyWakeCompleted = YES;
                weakSelf.lastTest.stringValue = @"Réveil RTP historique impossible · ouvrez Réglages réseau MIDI";
            });
            return;
        }
        NSTask *reconnectTask = [[NSTask alloc] init];
        reconnectTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
        reconnectTask.arguments = @[reconnectScript, peer, peer];
        NSPipe *pipe = [NSPipe pipe];
        reconnectTask.standardOutput = pipe;
        reconnectTask.standardError = pipe;
        weakSelf.legacyWakeTask = reconnectTask;
        reconnectTask.terminationHandler = ^(NSTask *reconnected) {
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.legacyWakeRunning = NO;
                weakSelf.legacyWakeCompleted = YES;
                if (reconnected.terminationStatus == 0) {
                    weakSelf.lastTest.stringValue = [NSString stringWithFormat:@"✓ Session RTP historique réveillée · %@", peer];
                } else {
                    weakSelf.lastTest.stringValue = [NSString stringWithFormat:@"Réveil RTP historique incomplet · %@", output];
                }
                if (weakSelf.showModeEnabled) [weakSelf updateCompactSummary];
            });
        };
        NSError *reconnectError = nil;
        if (![reconnectTask launchAndReturnError:&reconnectError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.legacyWakeRunning = NO;
                weakSelf.legacyWakeCompleted = YES;
                weakSelf.lastTest.stringValue = @"Impossible de lancer la reconnexion RTP historique";
            });
        }
    };
    NSError *openError = nil;
    if (![openTask launchAndReturnError:&openError]) {
        self.legacyWakeRunning = NO;
        self.legacyWakeCompleted = YES;
        self.lastTest.stringValue = @"Impossible d’ouvrir les réglages réseau MIDI";
    }
}

- (void)refreshTargetMenu {
    NSString *selected = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    NSMutableArray<NSString *> *available = [self.discoveredPeers.array mutableCopy];
    if (self.localNetworkName.length) [available removeObject:self.localNetworkName];
    NSString *computerName = NSHost.currentHost.localizedName;
    if (computerName.length) [available removeObject:computerName];
    NSArray<NSString *> *names = [available sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    // The RTP peer is a computer/session name, not a Yamaha console identity.
    // Forget stale machine names and adopt the currently advertised peer.
    // CL5 and QL1 remain MIDI channel labels.
    BOOL adoptedPeer = NO;
    if (!selected.length || ![names containsObject:selected]) {
        selected = names.firstObject;
        if (selected.length) {
            [[NSUserDefaults standardUserDefaults] setObject:selected forKey:@"preferredRtpPeer"];
            adoptedPeer = YES;
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"preferredRtpPeer"];
        }
    }
    [self.targetMenu removeAllItems];
    [self.targetMenu addItemsWithTitles:names.count ? names : @[@"Aucun correspondant découvert"]];
    if (selected.length && [names containsObject:selected]) [self.targetMenu selectItemWithTitle:selected];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    self.connectButton.enabled = names.count > 0;
    self.technicalPeers.stringValue = names.count
        ? [NSString stringWithFormat:@"%lu détecté(s)\n%@", (unsigned long)names.count, [names componentsJoinedByString:@" · "]]
        : @"Aucun correspondant _apple-midi._udp détecté";
    if (adoptedPeer) {
        self.legacyWakeCompleted = NO;
        [self restartGuardianForPeer:selected];
        [self ensureLegacyWakeIfNeeded];
    }
    [self writeConsoleReturnState];
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
    if (service.name.length) {
        [self.discoveredPeers addObject:service.name];
        self.peerServices[service.name] = service;
        service.delegate = self;
        [service resolveWithTimeout:3.0];
    }
    if (!moreComing) [self refreshTargetMenu];
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    if (sender.name.length && sender.hostName.length) self.peerHosts[sender.name] = sender.hostName;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length) [self.discoveredPeers removeObject:service.name];
    if (service.name.length) { [self.peerServices removeObjectForKey:service.name]; [self.peerHosts removeObjectForKey:service.name]; }
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
    [self selectPassiveReturnSourceNamed:endpoint];
    BOOL hasSource = [sources containsObject:endpoint];
    BOOL hasDestination = [destinations containsObject:endpoint];
    MIDINetworkSession *session = [MIDINetworkSession defaultSession];
    self.technicalSession.stringValue = [NSString stringWithFormat:@"Réglages : gérés par macOS\nCorrespondants API détectés : %lu\nValidation : test aller-retour",
        (unsigned long)session.connections.count];
    self.technicalEndpoints.stringValue = [NSString stringWithFormat:@"Entrées : %lu   Sorties : %lu\nPorts RTP détectés : %lu\nCoreMIDI : %@",
        (unsigned long)sources.count, (unsigned long)destinations.count, (unsigned long)candidates.count,
        (sources.count || destinations.count) ? @"opérationnel" : @"aucun port"];
    self.technicalSelection.stringValue = [NSString stringWithFormat:@"%@\nEntrée : %@   Sortie : %@",
        endpoint.length ? endpoint : @"Aucun port", hasSource ? @"OUI" : @"NON", hasDestination ? @"OUI" : @"NON"];
    if (self.showModeEnabled) [self updateCompactSummary];

    if (self.loopDetectedEndpoint && [self.loopDetectedEndpoint isEqualToString:endpoint]) {
        [self setLamp:[NSColor systemRedColor] title:@"BOUCLE MIDI DÉTECTÉE" detail:@"Dans Ableton : désactivez Entrée RTP > Piste, puis relancez le test."];
    } else if (self.validatedEndpoint && [self.validatedEndpoint isEqualToString:endpoint]) {
        NSTimeInterval age = -[self.validatedAt timeIntervalSinceNow];
        [self setLamp:[NSColor systemGreenColor] title:@"RTP VALIDÉ" detail:[NSString stringWithFormat:@"Aller-retour confirmé il y a %.0f s sur %@", age, endpoint]];
    } else if (hasSource && hasDestination) {
        [self setLamp:[NSColor systemOrangeColor] title:@"RTP DISPONIBLE" detail:@"Le port est visible ; lancez un test pour valider le retour réel."];
    } else {
        [self setLamp:[NSColor systemRedColor] title:@"RTP HORS LIGNE" detail:@"Aucune paire entrée/sortie RTP exploitable n’est visible."];
    }
    [self writeConsoleReturnState];
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
                self.loopDetectedEndpoint = nil;
                self.validatedAt = [NSDate date];
                self.lastTest.stringValue = [NSString stringWithFormat:@"✓ %@ · canal %ld · PGM %ld confirmé · %@ ms", console, (long)channel, (long)program, latency];
                NSString *compactResult = [NSString stringWithFormat:@"PGM %ld confirmé · %@ ms", (long)program, latency];
                if (channel == 1) self.lastCL5Test = compactResult; else self.lastQL1Test = compactResult;
            } else {
                self.validatedEndpoint = nil;
                BOOL loopDetected = [output rangeOfString:@"LOOP_DETECTED"].location != NSNotFound;
                if (loopDetected) self.loopDetectedEndpoint = endpoint;
                NSString *reason = loopDetected ? @"boucle MIDI détectée · désactivez Entrée RTP > Piste dans Ableton"
                    : ([output rangeOfString:@"TIMEOUT"].location != NSNotFound ? @"aucun retour reçu" : @"test impossible");
                self.lastTest.stringValue = [NSString stringWithFormat:@"Échec : %@", reason];
                if (channel == 1) self.lastCL5Test = reason; else self.lastQL1Test = reason;
            }
            if (self.showModeEnabled) [self updateCompactSummary];
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
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    NSString *host = self.peerHosts[peer];
    if (!host.length) {
        self.lastTest.stringValue = @"Adresse du Mac distant indisponible · actualisez le diagnostic.";
        return;
    }
    BOOL shouldStop = self.remoteSimulatorRunning;
    if (!shouldStop) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Démarrer le simulateur sur l’autre Mac ?";
        alert.informativeText = [NSString stringWithFormat:@"Le simulateur sera lancé sur %@ pour le test aller-retour. Ne l’utilisez pas en même temps qu’une vraie console et arrêtez-le après le test.", peer];
        [alert addButtonWithTitle:@"Démarrer"];
        [alert addButtonWithTitle:@"Annuler"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    self.simulatorButton.enabled = NO;
    self.lastTest.stringValue = shouldStop ? @"Arrêt du simulateur distant…" : @"Démarrage du simulateur distant…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
        if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        struct addrinfo hints = {0}, *results = NULL;
        hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM;
        int lookup = getaddrinfo(host.UTF8String, "50022", &hints, &results);
        NSDictionary *command = @{@"service": @"cl-midi-rtp-control", @"action": shouldStop ? @"stop-simulator" : @"start-simulator"};
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
        ssize_t sent = (lookup == 0 && fd >= 0) ? sendto(fd, encoded.bytes, encoded.length, 0, results->ai_addr, results->ai_addrlen) : -1;
        UInt8 buffer[2048]; ssize_t received = sent >= 0 ? recv(fd, buffer, sizeof(buffer), 0) : -1;
        NSDictionary *reply = received > 0 ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:(NSUInteger)received] options:0 error:nil] : nil;
        if (results) freeaddrinfo(results); if (fd >= 0) close(fd);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.simulatorButton.enabled = YES;
            BOOL ok = [reply[@"ok"] boolValue];
            self.lastTest.stringValue = reply[@"message"] ?: @"Aucune réponse de l’agent RTP distant";
            if (ok) {
                self.remoteSimulatorRunning = !shouldStop;
                self.simulatorButton.title = self.remoteSimulatorRunning ? @"ARRÊTER LE SIMULATEUR DISTANT" : @"DÉMARRER LE SIMULATEUR DISTANT";
            }
        });
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    [self.timer invalidate];
    [self.serviceBrowser stop];
    if (self.guardianTask.running) [self.guardianTask terminate];
    if (self.legacyWakeTask.running) [self.legacyWakeTask terminate];
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
    }
    if (self.returnMonitorInputPort) MIDIPortDispose(self.returnMonitorInputPort);
    if (self.returnMonitorClient) MIDIClientDispose(self.returnMonitorClient);
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

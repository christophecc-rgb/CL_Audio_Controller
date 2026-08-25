#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <sys/file.h>
#import <sys/socket.h>
#import <fcntl.h>
#import <unistd.h>

static int CLBackgroundMonitorLock = -1;

static void CLInstallApplicationMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@""];
    NSString *appName = NSProcessInfo.processInfo.processName;
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[@"Quitter " stringByAppendingString:appName]
                                                     action:@selector(terminate:)
                                              keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [applicationMenu addItem:quitItem];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];
    NSApp.mainMenu = mainMenu;
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

static void CLAppendDiagnostic(NSString *event, NSString *detail) {
    NSString *logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
    NSString *path = [logs stringByAppendingPathComponent:@"CL MIDI Network Assistant.log"];
    [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *line = [NSString stringWithFormat:@"%@\t%@\t%@\n", NSDate.date, event ?: @"event", detail ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [data writeToFile:path atomically:YES];
    else {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static BOOL CLPostDoubleClickFromConnectorReason(NSString *reason) {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"CL_CLICK:([0-9]+),([0-9]+)" options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:reason ?: @"" options:0 range:NSMakeRange(0, reason.length)];
    if (!match || match.numberOfRanges < 3) return NO;
    CGFloat x = [[reason substringWithRange:[match rangeAtIndex:1]] doubleValue];
    CGFloat y = [[reason substringWithRange:[match rangeAtIndex:2]] doubleValue];
    CGPoint point = CGPointMake(x, y);
    NSRunningApplication *audioMIDISetup = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.audio.AudioMIDISetup"].firstObject;
    [audioMIDISetup activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    usleep(350000);
    for (int click = 1; click <= 2; click++) {
        CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
        CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
        if (!down || !up) {
            if (down) CFRelease(down);
            if (up) CFRelease(up);
            return NO;
        }
        CGEventSetIntegerValueField(down, kCGMouseEventClickState, click);
        CGEventSetIntegerValueField(up, kCGMouseEventClickState, click);
        CGEventPost(kCGSessionEventTap, down);
        usleep(30000);
        CGEventPost(kCGSessionEventTap, up);
        CFRelease(down);
        CFRelease(up);
        usleep(120000);
    }
    return YES;
}

@interface CLNetworkDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property NSWindow *window;
@property NSView *headerPanel;
@property NSView *statusPanel;
@property NSView *targetPanel;
@property NSView *testPanel;
@property NSTextField *rtpTestTitle;
@property NSView *technicalPanel;
@property NSTextField *appTitleLabel;
@property NSTextField *appSubtitleLabel;
@property NSTextField *compactSummary;
@property NSTextField *footerLabel;
@property NSButton *showModeButton;
@property NSButton *settingsButton;
@property NSButton *refreshButton;
@property BOOL showModeEnabled;
@property BOOL backgroundMonitorOnly;
@property BOOL ownsPassiveReturnMonitor;
@property NSString *lastCL5Test;
@property NSString *lastQL1Test;
@property NSView *lamp;
@property NSTextField *headline;
@property NSTextField *detail;
@property NSTextField *lastTest;
@property NSPopUpButton *endpointMenu;
@property NSPopUpButton *returnModeMenu;
@property NSTextField *programField;
@property NSPopUpButton *testTargetMenu;
@property NSButton *testButton;
@property NSPopUpButton *targetMenu;
@property NSButton *connectButton;
@property NSTimer *timer;
@property NSNetServiceBrowser *serviceBrowser;
@property NSNetServiceBrowser *agentServiceBrowser;
@property NSMutableOrderedSet<NSString *> *discoveredPeers;
@property NSMutableDictionary<NSString *, NSNetService *> *peerServices;
@property NSMutableDictionary<NSString *, NSString *> *peerHosts;
@property NSMutableDictionary<NSString *, NSString *> *rtpPeerHosts;
@property NSMutableDictionary<NSString *, NSNumber *> *rtpPeerPorts;
@property BOOL remoteSimulatorRunning;
@property NSString *localNetworkName;
@property BOOL peerInspectionRunning;
@property NSString *validatedEndpoint;
@property NSDate *validatedAt;
@property NSString *lastRTPTestStatus;
@property NSNumber *lastRTPTestLatencyMs;
@property NSString *lastRTPTestMessage;
@property NSDate *lastRTPTestAt;
@property NSString *loopDetectedEndpoint;
@property NSView *simulatorPanel;
@property NSPopUpButton *simulatorModeMenu;
@property NSPopUpButton *simulatorEndpointMenu;
@property NSPopUpButton *simulatorInputEndpointMenu;
@property NSTextField *simulatorDelayField;
@property NSTextField *simulatorStatusLabel;
@property NSTextField *simulatorCL5MemoryField;
@property NSTextField *simulatorQL1MemoryField;
@property NSMutableArray<NSMutableDictionary *> *simulatorDevices;
@property NSMutableDictionary<NSString *, NSTask *> *simulatorTasks;
@property NSMutableDictionary<NSString *, NSMutableData *> *simulatorOutputBuffers;
@property NSStackView *simulatorDeviceRows;
@property NSTask *guardianTask;
@property NSString *guardianPeer;
@property NSString *guardianHost;
@property NSUInteger guardianPort;
@property NSString *guardianManagedPeer;
@property BOOL systemConnectRunning;
@property NSMutableSet<NSString *> *systemConnectAttemptedPeers;
@property NSMutableDictionary<NSString *, NSNumber *> *systemConnectRetryCounts;
@property NSTextField *technicalSession;
@property NSTextField *technicalEndpoints;
@property NSTextField *technicalPeers;
@property NSTextField *technicalSelection;
@property NSView *cl5ReturnCard;
@property NSView *ql1ReturnCard;
@property NSTextField *cl5ReturnProgram;
@property NSTextField *ql1ReturnProgram;
@property NSTextField *cl5ReturnState;
@property NSTextField *ql1ReturnState;
@property NSTextField *cl5ReturnTitle;
@property NSTextField *ql1ReturnTitle;
@property NSView *assistantReturnPanel;
@property NSView *assistantCL5ReturnCard;
@property NSView *assistantQL1ReturnCard;
@property NSTextField *assistantCL5ReturnProgram;
@property NSTextField *assistantQL1ReturnProgram;
@property NSTextField *assistantCL5ReturnState;
@property NSTextField *assistantQL1ReturnState;
@property NSTextField *assistantCL5ReturnTitle;
@property NSTextField *assistantQL1ReturnTitle;
@property NSString *currentAbletonSceneTitle;
@property NSDictionary *expectedCL5State;
@property NSDictionary *expectedQL1State;
@property MIDIClientRef returnMonitorClient;
@property MIDIEndpointRef localReturnDestination;
@property BOOL localReturnMode;
@property MIDIPortRef expectedMonitorInputPort;
@property MIDIEndpointRef expectedMonitorSource;
@property OSStatus expectedMonitorStatus;
@property MIDIPortRef returnMonitorInputPort;
@property MIDIEndpointRef returnMonitorSource;
@property OSStatus returnMonitorStatus;
@property NSInteger lastCL5Program;
@property NSInteger lastQL1Program;
@property NSDate *lastCL5ProgramAt;
@property NSDate *lastQL1ProgramAt;
@property NSString *lastCL5Title;
@property NSString *lastQL1Title;
@property NSInteger expectedCL5Program;
@property NSInteger expectedQL1Program;
@property NSDate *expectedCL5ProgramAt;
@property NSDate *expectedQL1ProgramAt;
@property NSUInteger sceneTitleTraceSequence;
@property NSUInteger cl5SceneTitleLookupGeneration;
@property NSUInteger ql1SceneTitleLookupGeneration;
- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel;
- (void)queueExpectedProgram:(UInt8)program channel:(UInt8)channel;
- (void)resolveSceneTitleForMIDIProgram:(NSInteger)midiProgram channel:(UInt8)channel;
- (void)updateConsoleReturnCards;
- (void)updateRoundTripPanelForCurrentMode;
- (void)refreshAbletonSceneTitle;
- (void)recordSimulatorProgram:(NSInteger)program channel:(NSInteger)channel;
- (void)recordSimulatorProgram:(NSInteger)program deviceID:(NSString *)deviceID;
@end

static NSString *const CLExpectedEndpointName = @"Gestionnaire IAC Bus 1";
static NSString *const CLLocalReturnEndpointName = @"CL MIDI Return Test";
static NSString *const CLRTPReturnEndpointName = @"Réseau RTP MB Chris";

static BOOL CLIsRTPReturnEndpointName(NSString *name) {
    if (!name.length || [name isEqualToString:CLExpectedEndpointName] ||
        [name isEqualToString:CLLocalReturnEndpointName]) return NO;
    return [name rangeOfString:@"RTP" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"Réseau" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSArray<NSString *> *CLLocalRTPEndpointNames(void) {
    NSArray<NSString *> *sources = EndpointNames(YES);
    NSSet<NSString *> *destinations = [NSSet setWithArray:EndpointNames(NO)];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (NSString *name in sources) {
        if (CLIsRTPReturnEndpointName(name) && [destinations containsObject:name]) [names addObject:name];
    }
    return names.array;
}

static NSString *CLPreferredLocalRTPEndpoint(NSArray<NSString *> *endpoints) {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"simulatorLocalRtpEndpoint"];
    if (saved.length && [endpoints containsObject:saved]) return saved;
    for (NSString *keyword in @[@"QL1 simulator", @"simulator", @"QL1"]) {
        for (NSString *name in endpoints) {
            if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return name;
        }
    }
    return endpoints.firstObject;
}

static NSArray<NSString *> *CLSimulatorInputEndpointNames(void) {
    return EndpointNames(YES);
}

static void CLPassiveExpectedRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)srcConnRefCon;
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 status = packet->data[index];
            if ((status & 0xF0) == 0xC0 && index + 1 < packet->length) {
                [delegate queueExpectedProgram:packet->data[index + 1] channel:(status & 0x0F) + 1];
                index += 2;
            } else index += 1;
        }
        packet = MIDIPacketNext(packet);
    }
}

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

static NSString *CLMidiAgeDescription(NSTimeInterval age) {
    NSInteger seconds = MAX(0, (NSInteger)floor(age));
    if (seconds < 2) return @"à l’instant";
    if (seconds < 60) return [NSString stringWithFormat:@"il y a %ld s", (long)seconds];
    NSInteger minutes = seconds / 60;
    if (minutes < 60) return [NSString stringWithFormat:@"il y a %ld min", (long)minutes];
    NSInteger hours = minutes / 60;
    NSInteger remainingMinutes = minutes % 60;
    return remainingMinutes
        ? [NSString stringWithFormat:@"il y a %ld h %ld min", (long)hours, (long)remainingMinutes]
        : [NSString stringWithFormat:@"il y a %ld h", (long)hours];
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
    CLInstallApplicationMenu();
    self.backgroundMonitorOnly = [NSProcessInfo.processInfo.arguments containsObject:@"--background-monitor"];
    CLBackgroundMonitorLock = open("/private/tmp/CL_MIDI_Console_Monitor.lock", O_CREAT | O_RDWR, 0600);
    self.ownsPassiveReturnMonitor = CLBackgroundMonitorLock >= 0 && flock(CLBackgroundMonitorLock, LOCK_EX | LOCK_NB) == 0;
    if (self.backgroundMonitorOnly && !self.ownsPassiveReturnMonitor) {
            CLAppendDiagnostic(@"background-monitor-skipped", @"une instance de surveillance est déjà active");
            [NSApp terminate:nil];
            return;
    }
    NSString *bundleExecutablePath = NSBundle.mainBundle.executablePath ?: @"";
    BOOL runningFromAppBundle = [bundleExecutablePath containsString:@".app/Contents/MacOS/"];
    if (runningFromAppBundle) {
        [self installBackgroundLaunchAgent];
    } else {
        CLAppendDiagnostic(@"background-monitor-not-installed", @"mode développement : LaunchAgent non installé");
    }

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 900)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI Network Assistant";
    self.lastCL5Test = @"non testé";
    self.lastQL1Test = @"non testé";
    self.lastRTPTestStatus = @"idle";
    self.lastRTPTestLatencyMs = nil;
    self.lastRTPTestMessage = @"Aucun aller-retour validé";
    self.lastRTPTestAt = nil;
    self.lastCL5Program = -1;
    self.lastQL1Program = -1;
    self.expectedCL5Program = -1;
    self.expectedQL1Program = -1;
    NSUserDefaults *returnDefaults = NSUserDefaults.standardUserDefaults;
    if ([returnDefaults objectForKey:@"lastCL5Program"] != nil) {
        self.lastCL5Program = [returnDefaults integerForKey:@"lastCL5Program"];
        NSTimeInterval timestamp = [returnDefaults doubleForKey:@"lastCL5ProgramAt"];
        if (timestamp > 0) self.lastCL5ProgramAt = [NSDate dateWithTimeIntervalSince1970:timestamp];
        self.lastCL5Title = [returnDefaults stringForKey:@"lastCL5Title"] ?: @"";
    }
    if ([returnDefaults objectForKey:@"lastQL1Program"] != nil) {
        self.lastQL1Program = [returnDefaults integerForKey:@"lastQL1Program"];
        NSTimeInterval timestamp = [returnDefaults doubleForKey:@"lastQL1ProgramAt"];
        if (timestamp > 0) self.lastQL1ProgramAt = [NSDate dateWithTimeIntervalSince1970:timestamp];
        self.lastQL1Title = [returnDefaults stringForKey:@"lastQL1Title"] ?: @"";
    }
    self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.045 blue:0.060 alpha:1.0];
    [self.window center];
    if (!self.backgroundMonitorOnly) [self.window makeKeyAndOrderFront:nil];

    NSView *content = self.window.contentView;

    NSView *header = self.headerPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 796, 468, 88)];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.023 blue:0.032 alpha:1.0].CGColor;
    header.layer.cornerRadius = 12.0;
    header.layer.borderWidth = 1.0;
    header.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor;
    [content addSubview:header];

    NSMutableArray<NSString *> *logoCandidates = [NSMutableArray array];

    NSString *resourcePath = NSBundle.mainBundle.resourcePath;
    if (resourcePath.length) {
        [logoCandidates addObject:
            [resourcePath stringByAppendingPathComponent:@"paradis_latin_logo.jpg"]];
        [logoCandidates addObject:
            [resourcePath stringByAppendingPathComponent:@"cl_audio_logo.png"]];
        [logoCandidates addObject:
            [resourcePath stringByAppendingPathComponent:@"assets/cl_audio_logo.png"]];
    }

    NSString *executablePath =
        NSProcessInfo.processInfo.arguments.firstObject.stringByStandardizingPath;
    NSString *executableDirectory =
        executablePath.stringByDeletingLastPathComponent;

    if (executableDirectory.length) {
        [logoCandidates addObject:
            [executableDirectory stringByAppendingPathComponent:@"paradis_latin_logo.jpg"]];
        [logoCandidates addObject:
            [executableDirectory stringByAppendingPathComponent:@"cl_audio_logo.png"]];

        NSString *repositoryRoot =
            [[[executableDirectory stringByDeletingLastPathComponent]
                stringByDeletingLastPathComponent]
                    stringByDeletingLastPathComponent];

        [logoCandidates addObject:
            [repositoryRoot stringByAppendingPathComponent:
                @"M4L/Install/paradis_latin_logo.jpg"]];
        [logoCandidates addObject:
            [repositoryRoot stringByAppendingPathComponent:
                @"assets/cl_audio_logo.png"]];
        [logoCandidates addObject:
            [repositoryRoot stringByAppendingPathComponent:
                @"cl_audio_logo.png"]];
    }

    NSString *logoPath = nil;
    for (NSString *candidate in logoCandidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
            logoPath = candidate;
            break;
        }
    }

    NSImage *logo = logoPath.length
        ? [[NSImage alloc] initWithContentsOfFile:logoPath]
        : nil;

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
    self.showModeButton = [self accentButton:@"Diagnostic détaillé" frame:NSMakeRect(354, 741, 130, 30) action:@selector(toggleShowMode:) color:[NSColor colorWithRed:0.24 green:0.28 blue:0.35 alpha:1.0]];
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
    [targetPanel addSubview:[self label:@"MODE RETOUR" frame:NSMakeRect(16, 68, 150, 20) size:10 bold:YES]];
    [targetPanel addSubview:[self label:@"CONSOLE DISTANTE RTP" frame:NSMakeRect(194, 68, 180, 20) size:10 bold:YES]];
    self.returnModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 24, 168, 34) pullsDown:NO];
    [self.returnModeMenu addItemsWithTitles:@[@"RTP distant", @"Test local dédié"]];
    self.returnModeMenu.target = self;
    self.returnModeMenu.action = @selector(returnModeChanged:);
    NSString *savedReturnMode = [NSUserDefaults.standardUserDefaults stringForKey:@"consoleReturnMode"];
    [self.returnModeMenu selectItemAtIndex:[savedReturnMode isEqualToString:@"local_dedicated"] ? 1 : 0];
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 1;
    [self stylePopup:self.returnModeMenu accent:[NSColor colorWithRed:0.92 green:0.58 blue:0.26 alpha:1.0]];
    [targetPanel addSubview:self.returnModeMenu];
    self.targetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(194, 24, 166, 34) pullsDown:NO];
    self.targetMenu.target = self;
    self.targetMenu.action = @selector(targetChanged:);
    [self.targetMenu addItemWithTitle:@"Recherche des correspondants…"];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    [targetPanel addSubview:self.targetMenu];
    self.connectButton = [self accentButton:@"Connecter" frame:NSMakeRect(370, 23, 82, 36) action:@selector(connectSelectedPeer:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.82 alpha:1.0]];
    [targetPanel addSubview:self.connectButton];

    NSView *testPanel = self.testPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 390, 468, 96)];
    testPanel.wantsLayer = YES; testPanel.layer.cornerRadius = 12; testPanel.layer.borderWidth = 1;
    testPanel.layer.backgroundColor = [NSColor colorWithRed:0.065 green:0.073 blue:0.09 alpha:1.0].CGColor;
    testPanel.layer.borderColor = [NSColor colorWithRed:0.38 green:0.30 blue:0.65 alpha:0.7].CGColor; [content addSubview:testPanel];
    self.rtpTestTitle = [self label:@"DIAGNOSTIC DISTANT · VÉRIFIER RTP" frame:NSMakeRect(16, 68, 340, 18) size:10 bold:YES];
    [testPanel addSubview:self.rtpTestTitle];
    self.endpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 30, 156, 30) pullsDown:NO];
    self.endpointMenu.target = self;
    self.endpointMenu.action = @selector(endpointChanged:);
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];
    [testPanel addSubview:self.endpointMenu];
    self.testTargetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, 30, 105, 30) pullsDown:NO];
    [self.testTargetMenu addItemsWithTitles:@[@"CL5 · Ch.1", @"QL1 · Ch.2"]];
    [self stylePopup:self.testTargetMenu accent:[NSColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:1.0]];
    [testPanel addSubview:self.testTargetMenu];
    self.programField = [[NSTextField alloc] initWithFrame:NSMakeRect(293, 30, 50, 30)];
    self.programField.stringValue = @"42";
    self.programField.alignment = NSTextAlignmentCenter;
    self.programField.font = [NSFont boldSystemFontOfSize:14.0];
    self.programField.textColor = [NSColor colorWithRed:0.55 green:0.90 blue:0.68 alpha:1.0];
    self.programField.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0];
    [testPanel addSubview:self.programField];
    self.testButton = [self accentButton:@"Vérifier RTP" frame:NSMakeRect(351, 29, 101, 32) action:@selector(runTest:) color:[NSColor colorWithRed:0.08 green:0.58 blue:0.32 alpha:1.0]];
    [testPanel addSubview:self.testButton];

    self.lastTest = [self label:@"Aucun aller-retour validé" frame:NSMakeRect(16, 6, 436, 18) size:9 bold:YES];
    self.lastTest.maximumNumberOfLines = 1;
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

    self.cl5ReturnCard = [[NSView alloc] initWithFrame:NSMakeRect(16, 12, 210, 52)];
    self.ql1ReturnCard = [[NSView alloc] initWithFrame:NSMakeRect(236, 12, 216, 52)];
    for (NSView *card in @[self.cl5ReturnCard, self.ql1ReturnCard]) {
        card.wantsLayer = YES;
        card.layer.cornerRadius = 8;
        card.layer.borderWidth = 1;
        card.layer.backgroundColor = [NSColor colorWithRed:0.045 green:0.055 blue:0.070 alpha:1.0].CGColor;
        card.layer.borderColor = [NSColor colorWithWhite:0.22 alpha:1.0].CGColor;
        [technicalPanel addSubview:card];
        card.hidden = YES;
    }
    self.cl5ReturnProgram = [self label:@"CL5 · scène n° —" frame:NSMakeRect(10, 33, 190, 16) size:11 bold:YES];
    self.ql1ReturnProgram = [self label:@"QL1 · scène n° —" frame:NSMakeRect(10, 33, 196, 16) size:11 bold:YES];
    self.cl5ReturnTitle = [self label:@"Titre Ableton en attente" frame:NSMakeRect(10, 18, 190, 14) size:9 bold:YES];
    self.ql1ReturnTitle = [self label:@"Titre Ableton en attente" frame:NSMakeRect(10, 18, 196, 14) size:9 bold:YES];
    self.cl5ReturnState = [self label:@"Aucun retour Program Change" frame:NSMakeRect(10, 3, 190, 14) size:8 bold:NO];
    self.ql1ReturnState = [self label:@"Aucun retour Program Change" frame:NSMakeRect(10, 3, 196, 14) size:8 bold:NO];
    [self.cl5ReturnCard addSubview:self.cl5ReturnProgram]; [self.cl5ReturnCard addSubview:self.cl5ReturnTitle]; [self.cl5ReturnCard addSubview:self.cl5ReturnState];
    [self.ql1ReturnCard addSubview:self.ql1ReturnProgram]; [self.ql1ReturnCard addSubview:self.ql1ReturnTitle]; [self.ql1ReturnCard addSubview:self.ql1ReturnState];

    self.assistantReturnPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 66, 468, 88)];
    [content addSubview:self.assistantReturnPanel];
    self.assistantCL5ReturnCard = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 228, 88)];
    self.assistantQL1ReturnCard = [[NSView alloc] initWithFrame:NSMakeRect(240, 0, 228, 88)];
    for (NSView *card in @[self.assistantCL5ReturnCard, self.assistantQL1ReturnCard]) {
        card.wantsLayer = YES;
        card.layer.cornerRadius = 9;
        card.layer.borderWidth = 2;
        [self.assistantReturnPanel addSubview:card];
    }
    self.assistantCL5ReturnProgram = [self label:@"CL5 · Scène attendue n°—" frame:NSMakeRect(11, 49, 206, 32) size:12 bold:YES];
    self.assistantQL1ReturnProgram = [self label:@"QL1 · Scène attendue n°—" frame:NSMakeRect(11, 49, 206, 32) size:12 bold:YES];
    self.assistantCL5ReturnTitle = [self label:@"Titre Ableton en attente" frame:NSMakeRect(11, 29, 206, 18) size:11 bold:YES];
    self.assistantQL1ReturnTitle = [self label:@"Titre Ableton en attente" frame:NSMakeRect(11, 29, 206, 18) size:11 bold:YES];
    self.assistantCL5ReturnState = [self label:@"En attente du premier retour MIDI" frame:NSMakeRect(11, 7, 206, 20) size:9 bold:NO];
    self.assistantQL1ReturnState = [self label:@"En attente du premier retour MIDI" frame:NSMakeRect(11, 7, 206, 20) size:9 bold:NO];
    self.assistantCL5ReturnState.maximumNumberOfLines = 2; self.assistantQL1ReturnState.maximumNumberOfLines = 2;
    [self.assistantCL5ReturnCard addSubview:self.assistantCL5ReturnProgram]; [self.assistantCL5ReturnCard addSubview:self.assistantCL5ReturnTitle]; [self.assistantCL5ReturnCard addSubview:self.assistantCL5ReturnState];
    [self.assistantQL1ReturnCard addSubview:self.assistantQL1ReturnProgram]; [self.assistantQL1ReturnCard addSubview:self.assistantQL1ReturnTitle]; [self.assistantQL1ReturnCard addSubview:self.assistantQL1ReturnState];

    self.settingsButton = [self accentButton:@"Réglages réseau MIDI" frame:NSMakeRect(16, 88, 228, 36) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.27 green:0.36 blue:0.49 alpha:1.0]]; [content addSubview:self.settingsButton];
    self.refreshButton = [self accentButton:@"Actualiser le diagnostic" frame:NSMakeRect(256, 88, 228, 36) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.30 green:0.35 blue:0.43 alpha:1.0]]; [content addSubview:self.refreshButton];
    [self createIntegratedSimulatorPanelInView:content];
    NSTextField *footer = self.footerLabel = [self label:@"CL AUDIO · MIDI NETWORK · 2026" frame:NSMakeRect(16, 10, 468, 18) size:8 bold:YES];
    footer.alignment = NSTextAlignmentCenter; footer.textColor = [NSColor colorWithWhite:0.38 alpha:1.0]; [content addSubview:footer];
    self.compactSummary = [self label:@"Aucun test aller-retour validé" frame:NSMakeRect(24, 66, 452, 54) size:12 bold:YES];
    self.compactSummary.maximumNumberOfLines = 3; self.compactSummary.hidden = YES; [content addSubview:self.compactSummary];

    [self refreshEndpoints];
    self.discoveredPeers = [NSMutableOrderedSet orderedSet];
    self.peerServices = [NSMutableDictionary dictionary];
    self.peerHosts = [NSMutableDictionary dictionary];
    self.rtpPeerHosts = [NSMutableDictionary dictionary];
    self.rtpPeerPorts = [NSMutableDictionary dictionary];
    self.systemConnectAttemptedPeers = [NSMutableSet set];
    self.systemConnectRetryCounts = [NSMutableDictionary dictionary];
    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.serviceBrowser.delegate = self;
    [self.serviceBrowser searchForServicesOfType:@"_apple-midi._udp." inDomain:@"local."];
    self.agentServiceBrowser = [[NSNetServiceBrowser alloc] init];
    self.agentServiceBrowser.delegate = self;
    [self.agentServiceBrowser searchForServicesOfType:@"_cl-midi-rtp-control._udp." inDomain:@"local."];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshTimer:) userInfo:nil repeats:YES];
    [self ensureGuardianRunning];
    if (self.ownsPassiveReturnMonitor) [self setupPassiveReturnMonitor];
    else [self loadPublishedConsoleReturnState];
    [self refreshAbletonSceneTitle];
    self.showModeEnabled = NO;
    [self applyPresentationMode];
    if (!self.backgroundMonitorOnly) [NSApp activateIgnoringOtherApps:YES];
}

- (void)installBackgroundLaunchAgent {
    NSString *executable = NSProcessInfo.processInfo.arguments.firstObject.stringByStandardizingPath;
    if (!executable.length || [executable containsString:@"/private/tmp/"]) return;
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    NSString *path = [directory stringByAppendingPathComponent:@"com.claudio.midi-network-monitor.plist"];
    NSDictionary *configuration = @{
        @"Label": @"com.claudio.midi-network-monitor",
        @"ProgramArguments": @[executable, @"--background-monitor"],
        @"RunAtLoad": @YES,
        @"KeepAlive": @YES,
        @"ThrottleInterval": @5,
        @"ProcessType": @"Background"
    };
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:configuration format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (plist.length) [plist writeToFile:path options:NSDataWritingAtomic error:nil];
}

- (void)loadPublishedConsoleReturnState {
    NSData *data = [NSData dataWithContentsOfFile:@"/private/tmp/CL_MIDI_Console_State.json"];
    NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![payload[@"service"] isEqualToString:@"cl-midi-console-monitor"]) return;
    NSDictionary *cl5 = payload[@"cl5"], *ql1 = payload[@"ql1"];
    if (cl5[@"expected_midi_program"] != nil && cl5[@"expected_midi_program"] != NSNull.null) {
        self.expectedCL5Program = [cl5[@"expected_midi_program"] integerValue];
        self.expectedCL5ProgramAt = [NSDate dateWithTimeIntervalSince1970:[cl5[@"expected_activated_at"] doubleValue]];
    }
    if (ql1[@"expected_midi_program"] != nil && ql1[@"expected_midi_program"] != NSNull.null) {
        self.expectedQL1Program = [ql1[@"expected_midi_program"] integerValue];
        self.expectedQL1ProgramAt = [NSDate dateWithTimeIntervalSince1970:[ql1[@"expected_activated_at"] doubleValue]];
    }
    if ([cl5[@"received"] boolValue]) {
        self.lastCL5Program = cl5[@"midi_program"] != nil && cl5[@"midi_program"] != NSNull.null
            ? [cl5[@"midi_program"] integerValue]
            : [cl5[@"program"] integerValue] - 1;
        self.lastCL5ProgramAt = [NSDate dateWithTimeIntervalSince1970:[cl5[@"received_at"] doubleValue]];
        self.lastCL5Title = @"Titre non résolu";
        [self resolveSceneTitleForMIDIProgram:self.lastCL5Program channel:1];
        [self recordSimulatorProgram:self.lastCL5Program channel:1];
    }
    if ([ql1[@"received"] boolValue]) {
        self.lastQL1Program = ql1[@"midi_program"] != nil && ql1[@"midi_program"] != NSNull.null
            ? [ql1[@"midi_program"] integerValue]
            : [ql1[@"program"] integerValue] - 1;
        self.lastQL1ProgramAt = [NSDate dateWithTimeIntervalSince1970:[ql1[@"received_at"] doubleValue]];
        self.lastQL1Title = @"Titre non résolu";
        [self resolveSceneTitleForMIDIProgram:self.lastQL1Program channel:2];
        [self recordSimulatorProgram:self.lastQL1Program channel:2];
    }
    [self updateConsoleReturnCards];
}

- (void)writeConsoleReturnState {
    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    NSString *returnMode = self.localReturnMode ? @"local_dedicated" : @"rtp_remote";
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    BOOL endpointAvailable =
        endpoint.length > 0 &&
        ![endpoint hasPrefix:@"Aucun"];

    BOOL endpointValidated =
        [self.lastRTPTestStatus isEqualToString:@"validated"] &&
        self.validatedEndpoint &&
        [self.validatedEndpoint isEqualToString:endpoint];

    BOOL loopDetected =
        self.loopDetectedEndpoint &&
        [self.loopDetectedEndpoint isEqualToString:endpoint];

    NSString *testText =
        self.lastRTPTestMessage.length
            ? self.lastRTPTestMessage
            : (self.lastTest.stringValue ?: @"");

    NSString *testStatus =
        self.lastRTPTestStatus.length
            ? self.lastRTPTestStatus
            : (endpointAvailable ? @"available" : @"offline");

    if (endpointValidated) testStatus = @"validated";
    if (loopDetected) testStatus = @"loop_detected";

    NSInteger requestedProgram = self.programField.integerValue;
    NSInteger requestedChannel = self.testTargetMenu.indexOfSelectedItem + 1;
    NSString *requestedConsole = requestedChannel == 2 ? @"QL1" : @"CL5";
    BOOL requestedSceneIsValid = requestedProgram >= 1 && requestedProgram <= 128;

    id latencyValue =
        self.lastRTPTestLatencyMs ?: NSNull.null;

    NSDictionary *payload = @{
        @"schema_version": @3,
        @"service": @"cl-midi-console-monitor",
        @"source": @"CL MIDI Network Assistant",
        @"updated_at": @(now),
        @"online": @YES,
        @"return_mode": returnMode,
        @"return_source": endpoint,
        @"monitor_source": self.localReturnMode ? CLLocalReturnEndpointName :
            (self.returnMonitorSource ? EndpointName(self.returnMonitorSource) : @""),
        @"monitor_status": @(self.returnMonitorStatus),
        @"expected_monitor_source": self.expectedMonitorSource
            ? EndpointName(self.expectedMonitorSource) : @"",
        @"expected_monitor_status": @(self.expectedMonitorStatus),
        @"return_monitor_source": self.localReturnMode ? CLLocalReturnEndpointName :
            (self.returnMonitorSource ? EndpointName(self.returnMonitorSource) : @""),
        @"return_monitor_status": @(self.returnMonitorStatus),

        @"rtp": @{
            @"peer": peer,
            @"endpoint": endpoint,
            @"available": @(endpointAvailable),
            @"validated": @(endpointValidated),
            @"loop_detected": @(loopDetected),
            @"status": testStatus,
            @"latency_ms": latencyValue,
            @"last_test":
                self.lastRTPTestMessage.length
                    ? self.lastRTPTestMessage
                    : testText,
            @"validated_at": self.validatedAt
                ? @([self.validatedAt timeIntervalSince1970])
                : NSNull.null,
        },

        @"test": @{
            @"status": testStatus,
            @"console": requestedConsole,
            @"channel": @(requestedChannel),
            @"program": @(requestedProgram),
            @"midi_program": requestedSceneIsValid
                ? @(requestedProgram - 1)
                : NSNull.null,
            @"scene": requestedSceneIsValid
                ? @(requestedProgram)
                : NSNull.null,
            @"latency_ms": latencyValue,
            @"updated_at": self.lastRTPTestAt
                ? @([self.lastRTPTestAt timeIntervalSince1970])
                : @(now),
        },

        @"cl5": @{
            @"expected_midi_program": self.expectedCL5Program >= 0 ? @(self.expectedCL5Program) : NSNull.null,
            @"expected_program": self.expectedCL5Program >= 0 ? @(self.expectedCL5Program + 1) : NSNull.null,
            @"expected_scene_memory": self.expectedCL5Program >= 0 ? @(self.expectedCL5Program + 1) : NSNull.null,
            @"expected_title": (self.expectedCL5State[@"expected_midi_program"] != NSNull.null &&
                [self.expectedCL5State[@"expected_midi_program"] integerValue] == self.expectedCL5Program)
                ? (self.expectedCL5State[@"expected_title"] ?: @"Titre non résolu") : @"Titre non résolu",
            @"expected_program_source": self.expectedCL5Program >= 0 ? @"ableton_iac_output" : @"unavailable",
            @"expected_title_source": (self.expectedCL5Program >= 0 &&
                [self.expectedCL5State[@"expected_title_source"] isEqual:@"console_clf"])
                ? @"console_clf" : @"unresolved",
            @"expected_activated_at": self.expectedCL5ProgramAt ? @([self.expectedCL5ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"returned_midi_program": self.lastCL5Program >= 0 ? @(self.lastCL5Program) : NSNull.null,
            @"returned_program": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"returned_scene_memory": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"returned_title": self.lastCL5Title.length ? self.lastCL5Title : @"Titre non résolu",
            @"returned_program_source": self.lastCL5Program >= 0 ? @"physical_midi" : @"unavailable",
            @"returned_title_source": self.lastCL5Title.length ? @"console_clf" : @"unresolved",
            @"returned_at": self.lastCL5ProgramAt ? @([self.lastCL5ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"program": self.lastCL5Program >= 0
                ? @(self.lastCL5Program + 1)
                : NSNull.null,
            @"midi_program": self.lastCL5Program >= 0
                ? @(self.lastCL5Program)
                : NSNull.null,
            @"scene": self.lastCL5Program >= 0
                ? @(self.lastCL5Program + 1)
                : NSNull.null,
            @"title": self.lastCL5Title ?: @"",
            @"received": @(self.lastCL5Program >= 0),
            @"received_at": self.lastCL5ProgramAt
                ? @([self.lastCL5ProgramAt timeIntervalSince1970])
                : NSNull.null,
            @"age_seconds": self.lastCL5ProgramAt
                ? @(MAX(0.0, -[self.lastCL5ProgramAt timeIntervalSinceNow]))
                : NSNull.null,
            @"fresh": @(self.lastCL5ProgramAt &&
                MAX(0.0, -[self.lastCL5ProgramAt timeIntervalSinceNow]) <= 12.0),
        },

        @"ql1": @{
            @"expected_midi_program": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program) : NSNull.null,
            @"expected_program": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program + 1) : NSNull.null,
            @"expected_scene_memory": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program + 1) : NSNull.null,
            @"expected_title": (self.expectedQL1State[@"expected_midi_program"] != NSNull.null &&
                [self.expectedQL1State[@"expected_midi_program"] integerValue] == self.expectedQL1Program)
                ? (self.expectedQL1State[@"expected_title"] ?: @"Titre non résolu") : @"Titre non résolu",
            @"expected_program_source": self.expectedQL1Program >= 0 ? @"ableton_iac_output" : @"unavailable",
            @"expected_title_source": (self.expectedQL1Program >= 0 &&
                [self.expectedQL1State[@"expected_title_source"] isEqual:@"console_clf"])
                ? @"console_clf" : @"unresolved",
            @"expected_activated_at": self.expectedQL1ProgramAt ? @([self.expectedQL1ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"returned_midi_program": self.lastQL1Program >= 0 ? @(self.lastQL1Program) : NSNull.null,
            @"returned_program": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"returned_scene_memory": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"returned_title": self.lastQL1Title.length ? self.lastQL1Title : @"Titre non résolu",
            @"returned_program_source": self.lastQL1Program >= 0 ? @"physical_midi" : @"unavailable",
            @"returned_title_source": self.lastQL1Title.length ? @"console_clf" : @"unresolved",
            @"returned_at": self.lastQL1ProgramAt ? @([self.lastQL1ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"program": self.lastQL1Program >= 0
                ? @(self.lastQL1Program + 1)
                : NSNull.null,
            @"midi_program": self.lastQL1Program >= 0
                ? @(self.lastQL1Program)
                : NSNull.null,
            @"scene": self.lastQL1Program >= 0
                ? @(self.lastQL1Program + 1)
                : NSNull.null,
            @"title": self.lastQL1Title ?: @"",
            @"received": @(self.lastQL1Program >= 0),
            @"received_at": self.lastQL1ProgramAt
                ? @([self.lastQL1ProgramAt timeIntervalSince1970])
                : NSNull.null,
            @"age_seconds": self.lastQL1ProgramAt
                ? @(MAX(0.0, -[self.lastQL1ProgramAt timeIntervalSinceNow]))
                : NSNull.null,
            @"fresh": @(self.lastQL1ProgramAt &&
                MAX(0.0, -[self.lastQL1ProgramAt timeIntervalSinceNow]) <= 12.0),
        },
    };

    NSData *data =
        [NSJSONSerialization dataWithJSONObject:payload
                                        options:0
                                          error:nil];

    [data writeToFile:@"/private/tmp/CL_MIDI_Console_State.json"
              options:NSDataWritingAtomic
                error:nil];

    [self updateConsoleReturnCards];
}

- (void)updateConsoleReturnCards {
    NSArray<NSDictionary *> *consoles = @[
        @{@"name": @"CL5", @"program": @(self.lastCL5Program), @"date": self.lastCL5ProgramAt ?: NSNull.null, @"title": self.lastCL5Title ?: @"",
          @"expected": self.expectedCL5State ?: @{},
          @"cards": @[self.cl5ReturnCard ?: NSNull.null, self.assistantCL5ReturnCard ?: NSNull.null],
          @"programLabels": @[self.cl5ReturnProgram ?: NSNull.null, self.assistantCL5ReturnProgram ?: NSNull.null],
          @"titleLabels": @[self.cl5ReturnTitle ?: NSNull.null, self.assistantCL5ReturnTitle ?: NSNull.null],
          @"stateLabels": @[self.cl5ReturnState ?: NSNull.null, self.assistantCL5ReturnState ?: NSNull.null]},
        @{@"name": @"QL1", @"program": @(self.lastQL1Program), @"date": self.lastQL1ProgramAt ?: NSNull.null, @"title": self.lastQL1Title ?: @"",
          @"expected": self.expectedQL1State ?: @{},
          @"cards": @[self.ql1ReturnCard ?: NSNull.null, self.assistantQL1ReturnCard ?: NSNull.null],
          @"programLabels": @[self.ql1ReturnProgram ?: NSNull.null, self.assistantQL1ReturnProgram ?: NSNull.null],
          @"titleLabels": @[self.ql1ReturnTitle ?: NSNull.null, self.assistantQL1ReturnTitle ?: NSNull.null],
          @"stateLabels": @[self.ql1ReturnState ?: NSNull.null, self.assistantQL1ReturnState ?: NSNull.null]}
    ];
    for (NSDictionary *console in consoles) {
        NSInteger program = [console[@"program"] integerValue];
        NSDate *date = console[@"date"] == NSNull.null ? nil : console[@"date"];
        NSTimeInterval age = date ? -date.timeIntervalSinceNow : DBL_MAX;
        NSDictionary *expected = console[@"expected"];
        id expectedProgramValue = expected[@"expected_program"] ?: expected[@"program"];
        BOOL hasExpectedProgram = expectedProgramValue && expectedProgramValue != NSNull.null;
        NSInteger expectedProgram = hasExpectedProgram ? [expectedProgramValue integerValue] : -1;
        NSString *expectedTitle = [expected[@"expected_title"] isKindOfClass:NSString.class]
            ? expected[@"expected_title"] : @"Titre non résolu";
        NSString *returnedTitle = [expected[@"returned_title"] isKindOfClass:NSString.class]
            ? expected[@"returned_title"] : @"Titre non résolu";
        id returnedSceneValue = expected[@"returned_scene_memory"];
        BOOL hasCanonicalReturn = returnedSceneValue && returnedSceneValue != NSNull.null;
        BOOL hasReturn = program >= 0 && date != nil && hasCanonicalReturn;
        BOOL stale = hasReturn && age > 12.0;
        NSInteger receivedScene = hasReturn ? [returnedSceneValue integerValue] : -1;
        NSString *validationStatus = [expected[@"validation_status"] isKindOfClass:NSString.class] ? expected[@"validation_status"] : @"unavailable";
        BOOL confirmed = [validationStatus isEqualToString:@"confirmed"];
        BOOL mismatch = [validationStatus isEqualToString:@"mismatch"];
        NSArray *cards = console[@"cards"], *programLabels = console[@"programLabels"], *titleLabels = console[@"titleLabels"], *stateLabels = console[@"stateLabels"];
        for (NSUInteger index = 0; index < cards.count; index++) {
            if (cards[index] == NSNull.null) continue;
            NSView *card = cards[index]; NSTextField *programLabel = programLabels[index]; NSTextField *titleLabel = titleLabels[index]; NSTextField *stateLabel = stateLabels[index];
            NSString *expectedText = hasExpectedProgram
                ? [NSString stringWithFormat:@"Scène attendue n°%ld", (long)expectedProgram]
                : @"Scène attendue n°—";
            NSString *receivedText = hasReturn
                ? [NSString stringWithFormat:@"Scène reçue n°%ld", (long)receivedScene]
                : @"";
            programLabel.stringValue = receivedText.length
                ? [NSString stringWithFormat:@"%@ · %@\n%@", console[@"name"], expectedText, receivedText]
                : [NSString stringWithFormat:@"%@ · %@", console[@"name"], expectedText];
            programLabel.maximumNumberOfLines = 2;
            stateLabel.stringValue = !hasReturn
                ? @"En attente du premier retour MIDI"
                : stale
                ? [NSString stringWithFormat:@"Dernière scène reçue %@", CLMidiAgeDescription(age)]
                : confirmed
                ? @"✓ Confirmée"
                : mismatch
                ? [NSString stringWithFormat:@"Attendue : %ld · Reçue : %ld · ✕ Mauvaise scène", (long)expectedProgram, (long)receivedScene]
                : @"Retour MIDI reçu · scène attendue indisponible";
            NSNumber *titleOffset = [expected[@"title_offset"] isKindOfClass:NSNumber.class] ? expected[@"title_offset"] : @0;
            id expectedLookup = expected[@"expected_title_lookup_memory"] ?: NSNull.null;
            id returnedLookup = expected[@"returned_title_lookup_memory"] ?: NSNull.null;
            titleLabel.stringValue = hasReturn
                ? [NSString stringWithFormat:@"Attendu : %@ · Reçu : %@ · offset %@%ld · lookup %@/%@", expectedTitle, returnedTitle, titleOffset.integerValue > 0 ? @"+" : @"", (long)titleOffset.integerValue, expectedLookup, returnedLookup]
                : [NSString stringWithFormat:@"Attendu : %@", expectedTitle];
            card.layer.backgroundColor = [NSColor colorWithRed:0.070 green:0.086 blue:0.110 alpha:1.0].CGColor;
            card.layer.borderColor = confirmed
                ? [NSColor colorWithRed:0.16 green:0.64 blue:0.32 alpha:1.0].CGColor
                : (mismatch ? [NSColor colorWithRed:0.78 green:0.22 blue:0.22 alpha:1.0].CGColor : (stale ? [NSColor colorWithRed:0.76 green:0.48 blue:0.16 alpha:1.0].CGColor : [NSColor colorWithWhite:0.23 alpha:1.0].CGColor));
            programLabel.textColor = [NSColor colorWithRed:0.93 green:0.77 blue:0.34 alpha:1.0];
            titleLabel.textColor = [NSColor colorWithWhite:0.78 alpha:1.0];
            stateLabel.textColor = confirmed ? [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0] : (mismatch ? [NSColor colorWithRed:1.0 green:0.40 blue:0.36 alpha:1.0] : (stale ? [NSColor colorWithRed:1.0 green:0.68 blue:0.30 alpha:1.0] : [NSColor colorWithWhite:0.62 alpha:1.0]));
        }
    }
}

- (void)refreshAbletonSceneTitle {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/status"];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (error || !data.length) return;
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *title = [payload[@"playing_scene_name"] isKindOfClass:NSString.class] ? payload[@"playing_scene_name"] : nil;
        NSDictionary *midiConsole = [payload[@"midi_console"] isKindOfClass:NSDictionary.class] ? payload[@"midi_console"] : @{};
        NSDictionary *cl5 = [midiConsole[@"cl5"] isKindOfClass:NSDictionary.class] ? midiConsole[@"cl5"] : @{};
        NSDictionary *ql1 = [midiConsole[@"ql1"] isKindOfClass:NSDictionary.class] ? midiConsole[@"ql1"] : @{};
        dispatch_async(dispatch_get_main_queue(), ^{
            if (title.length && ![title isEqualToString:@"—"]) self.currentAbletonSceneTitle = title;
            self.expectedCL5State = cl5;
            self.expectedQL1State = ql1;
            [self updateConsoleReturnCards];
        });
    }] resume];
}

- (NSUInteger)nextSceneTitleTraceSequence {
    @synchronized (self) {
        self.sceneTitleTraceSequence += 1;
        return self.sceneTitleTraceSequence;
    }
}

- (void)traceSceneTitleEvent:(NSString *)event
                 midiProgram:(NSInteger)midiProgram
                     channel:(UInt8)channel
                 lookupIndex:(NSInteger)lookupIndex
                receivedName:(NSString *)receivedName
                resolvedName:(NSString *)resolvedName {
    NSUInteger sequence = [self nextSceneTitleTraceSequence];
    CLAppendDiagnostic(@"scene-title-sync", [NSString stringWithFormat:
        @"order=%lu event=%@ channel=%u midi_program=%ld program=%ld scene=%ld lookup_index=%ld name_received=%@ name_resolved=%@",
        (unsigned long)sequence, event ?: @"", channel, (long)midiProgram,
        (long)midiProgram + 1, (long)midiProgram + 1, (long)lookupIndex,
        receivedName.length ? receivedName : @"—",
        resolvedName.length ? resolvedName : @"—"]);
}

- (void)resolveSceneTitleForMIDIProgram:(NSInteger)midiProgram channel:(UInt8)channel {
    NSInteger lookupIndex = midiProgram + 1;
    NSUInteger lookupGeneration;
    @synchronized (self) {
        if (channel == 1) lookupGeneration = ++self.cl5SceneTitleLookupGeneration;
        else lookupGeneration = ++self.ql1SceneTitleLookupGeneration;
    }
    [self traceSceneTitleEvent:@"lookup-requested" midiProgram:midiProgram channel:channel
                  lookupIndex:lookupIndex receivedName:nil resolvedName:nil];
    NSString *consoleKey = channel == 1 ? @"cl5" : @"ql1";
    NSString *urlString = [NSString stringWithFormat:
        @"http://127.0.0.1:5050/console-scene-title?console=%@&midi_program=%ld",
        consoleKey, (long)midiProgram];
    NSURL *url = [NSURL URLWithString:urlString];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        NSDictionary *payload = (!error && data.length)
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
            : nil;
        id returnedValue = payload[@"midi_program"];
        NSInteger returnedMIDIProgram = [returnedValue integerValue];
        NSString *receivedName = (
            [payload[@"ok"] boolValue] && returnedMIDIProgram == midiProgram &&
            [payload[@"title"] isKindOfClass:NSString.class]
        ) ? payload[@"title"] : @"";
        NSString *resolvedName = receivedName;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger currentProgram = channel == 1 ? self.lastCL5Program : self.lastQL1Program;
            NSUInteger currentGeneration = channel == 1
                ? self.cl5SceneTitleLookupGeneration
                : self.ql1SceneTitleLookupGeneration;
            BOOL stale = currentProgram != midiProgram || currentGeneration != lookupGeneration;
            [self traceSceneTitleEvent:stale ? @"lookup-stale" : @"lookup-completed"
                           midiProgram:midiProgram channel:channel lookupIndex:lookupIndex
                          receivedName:receivedName resolvedName:resolvedName];
            if (stale) return;
            if (channel == 1) self.lastCL5Title = resolvedName;
            else self.lastQL1Title = resolvedName;
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            [defaults setObject:resolvedName forKey:channel == 1 ? @"lastCL5Title" : @"lastQL1Title"];
            [self writeConsoleReturnState];
        });
    }] resume];
}

- (void)setupPassiveReturnMonitor {
    OSStatus clientStatus = MIDIClientCreate(CFSTR("CL Passive Console Return Monitor"), NULL, NULL, &_returnMonitorClient);
    OSStatus expectedPortStatus = clientStatus == noErr
        ? MIDIInputPortCreate(self.returnMonitorClient, CFSTR("Ableton expected input"), CLPassiveExpectedRead,
                              (__bridge void *)self, &_expectedMonitorInputPort)
        : clientStatus;
    OSStatus portStatus = clientStatus == noErr
        ? MIDIInputPortCreate(self.returnMonitorClient, CFSTR("Console return input"), CLPassiveReturnRead,
                              (__bridge void *)self, &_returnMonitorInputPort)
        : clientStatus;
    OSStatus localStatus = clientStatus == noErr
        ? MIDIDestinationCreate(self.returnMonitorClient, (__bridge CFStringRef)CLLocalReturnEndpointName,
                                CLPassiveReturnRead, (__bridge void *)self, &_localReturnDestination)
        : clientStatus;
    self.returnMonitorStatus = portStatus;
    self.expectedMonitorStatus = expectedPortStatus;
    if (clientStatus != noErr || portStatus != noErr || expectedPortStatus != noErr || localStatus != noErr) {
        self.lastTest.stringValue = @"Une écoute passive CoreMIDI est indisponible";
    }
    [self writeConsoleReturnState];
    // Le mode de présentation ne doit pas couper l'écoute MIDI. Les retours
    // physiques et ceux du simulateur restent des événements reçus, même si
    // l'utilisateur a choisi la lecture locale de secours.
    [self selectPassiveExpectedSourceNamed:CLExpectedEndpointName];
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 1;
    self.returnMonitorStatus = localStatus;
    if (!self.localReturnMode) [self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName];
    [self updateRoundTripPanelForCurrentMode];
}

- (void)selectPassiveExpectedSourceNamed:(NSString *)name {
    MIDIEndpointRef selectedSource = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) {
        MIDIEndpointRef source = MIDIGetSource(index);
        if ([EndpointName(source) isEqualToString:name]) { selectedSource = source; break; }
    }
    if (selectedSource == self.expectedMonitorSource) return;
    if (self.expectedMonitorSource && self.expectedMonitorInputPort) {
        MIDIPortDisconnectSource(self.expectedMonitorInputPort, self.expectedMonitorSource);
    }
    self.expectedMonitorSource = 0;
    if (selectedSource && self.expectedMonitorInputPort &&
        (self.expectedMonitorStatus = MIDIPortConnectSource(
            self.expectedMonitorInputPort, selectedSource, NULL)) == noErr) {
        self.expectedMonitorSource = selectedSource;
    } else if (!selectedSource) self.expectedMonitorStatus = kMIDIUnknownEndpoint;
}

- (void)selectPassiveReturnSourceNamed:(NSString *)name {
    if ([name isEqualToString:CLExpectedEndpointName] || [name isEqualToString:CLLocalReturnEndpointName]) {
        self.returnMonitorStatus = kMIDIUnknownEndpoint;
        return;
    }
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
        (self.returnMonitorStatus = MIDIPortConnectSource(
            self.returnMonitorInputPort, selectedSource, NULL
        )) == noErr) {
        self.returnMonitorSource = selectedSource;
    } else if (!selectedSource) {
        self.returnMonitorStatus = kMIDIUnknownEndpoint;
    }
    [self writeConsoleReturnState];
}

- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel {
    if (channel < 1 || channel > 16) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self recordSimulatorProgram:program channel:channel]; });
    if (channel != 1 && channel != 2) {
        return;
    }
    [self traceSceneTitleEvent:@"midi-callback" midiProgram:program channel:channel
                  lookupIndex:program receivedName:nil resolvedName:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (channel == 1) {
            self.lastCL5Program = program;
            self.lastCL5ProgramAt = [NSDate date];
            self.lastCL5Title = @"";
        } else {
            self.lastQL1Program = program;
            self.lastQL1ProgramAt = [NSDate date];
            self.lastQL1Title = @"";
        }
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (self.lastCL5Program >= 0) {
            [defaults setInteger:self.lastCL5Program forKey:@"lastCL5Program"];
            [defaults setDouble:self.lastCL5ProgramAt.timeIntervalSince1970 forKey:@"lastCL5ProgramAt"];
            [defaults setObject:self.lastCL5Title ?: @"" forKey:@"lastCL5Title"];
        }
        if (self.lastQL1Program >= 0) {
            [defaults setInteger:self.lastQL1Program forKey:@"lastQL1Program"];
            [defaults setDouble:self.lastQL1ProgramAt.timeIntervalSince1970 forKey:@"lastQL1ProgramAt"];
            [defaults setObject:self.lastQL1Title ?: @"" forKey:@"lastQL1Title"];
        }
        [self writeConsoleReturnState];
        [self resolveSceneTitleForMIDIProgram:program channel:channel];
        [self refreshAbletonSceneTitle];
    });
}

- (void)queueExpectedProgram:(UInt8)program channel:(UInt8)channel {
    if (channel != 1 && channel != 2) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDate *receivedAt = [NSDate date];
        if (channel == 1) {
            self.expectedCL5Program = program;
            self.expectedCL5ProgramAt = receivedAt;
        } else {
            self.expectedQL1Program = program;
            self.expectedQL1ProgramAt = receivedAt;
        }
        CLAppendDiagnostic(@"expected-midi", [NSString stringWithFormat:
            @"endpoint=%@ channel=%u midi_program=%u console=%@ role=expected",
            CLExpectedEndpointName, channel, program, channel == 1 ? @"CL5" : @"QL1"]);
        [self writeConsoleReturnState];
        [self refreshAbletonSceneTitle];
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
    [self applyPresentationMode];
}

- (void)applyPresentationMode {
    BOOL detailed = self.showModeEnabled;
    self.targetPanel.hidden = NO;
    self.technicalPanel.hidden = !detailed; self.settingsButton.hidden = !detailed;
    self.refreshButton.hidden = !detailed;
    self.assistantReturnPanel.hidden = detailed;
    self.simulatorPanel.hidden = NO;
    self.compactSummary.hidden = YES;
    self.showModeButton.title = detailed ? @"Vue Assistant" : @"Diagnostic détaillé";
    [self updateRoundTripPanelForCurrentMode];
    if (detailed) {
        [self.window setContentSize:NSMakeSize(500, 1100)];
        self.headerPanel.frame = NSMakeRect(16, 996, 468, 88);
        self.appTitleLabel.frame = NSMakeRect(20, 944, 270, 24);
        self.appSubtitleLabel.frame = NSMakeRect(286, 946, 94, 20);
        self.showModeButton.frame = NSMakeRect(354, 941, 130, 30);
        self.statusPanel.frame = NSMakeRect(16, 851, 468, 84);
        self.targetPanel.frame = NSMakeRect(16, 743, 468, 100); self.testPanel.frame = NSMakeRect(16, 639, 468, 96);
        self.technicalPanel.frame = NSMakeRect(16, 381, 468, 250);
        self.simulatorPanel.frame = NSMakeRect(16, 183, 468, 190);
        self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
    } else {
        [self.window setContentSize:NSMakeSize(500, 850)];
        self.headerPanel.frame = NSMakeRect(16, 746, 468, 88);
        self.appTitleLabel.frame = NSMakeRect(20, 694, 270, 24); self.appSubtitleLabel.frame = NSMakeRect(286, 696, 68, 20);
        self.showModeButton.frame = NSMakeRect(354, 691, 130, 30); self.statusPanel.frame = NSMakeRect(16, 601, 468, 84);
        self.targetPanel.frame = NSMakeRect(16, 493, 468, 100); self.testPanel.frame = NSMakeRect(16, 389, 468, 96);
        self.assistantReturnPanel.frame = NSMakeRect(16, 293, 468, 88);
        self.simulatorPanel.frame = NSMakeRect(16, 93, 468, 190);
        self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
    }
}

- (void)updateRoundTripPanelForCurrentMode {
    BOOL rtpMode = !self.localReturnMode;
    self.testPanel.hidden = !rtpMode;
    self.endpointMenu.enabled = rtpMode;
    self.testTargetMenu.enabled = rtpMode;
    self.programField.enabled = rtpMode;
    self.testButton.enabled = rtpMode;
    if (rtpMode) {
        self.rtpTestTitle.stringValue = @"DIAGNOSTIC DISTANT · VÉRIFIER RTP";
        self.testButton.title = @"Vérifier RTP";
    } else {
        self.lastTest.stringValue = @"Validation locale passive · expected / returned";
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

- (void)refreshTimer:(NSTimer *)timer {
    (void)timer;
    [self refreshEndpoints];
    [self refreshAbletonSceneTitle];
    [self ensureGuardianRunning];

    if (!self.ownsPassiveReturnMonitor) {
        if (CLBackgroundMonitorLock >= 0 &&
            flock(CLBackgroundMonitorLock, LOCK_EX | LOCK_NB) == 0) {
            self.ownsPassiveReturnMonitor = YES;
            [self setupPassiveReturnMonitor];
            CLAppendDiagnostic(@"passive-monitor-takeover", @"le Dashboard a repris automatiquement l’écoute MIDI");
        } else {
            [self loadPublishedConsoleReturnState];
        }
    }
}
- (void)refreshNow:(id)sender {
    (void)sender;
    [self refreshEndpoints];
    [self inspectMidiDirectory];
    self.lastTest.stringValue = @"Diagnostic actualisé · aucune reconnexion demandée";
    CLAppendDiagnostic(@"diagnostic-refresh", @"manual refresh only");
}
- (void)endpointChanged:(id)sender {
    (void)sender;

    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    if ([endpoint isEqualToString:CLExpectedEndpointName] || [endpoint isEqualToString:CLLocalReturnEndpointName]) {
        [self.endpointMenu selectItemWithTitle:CLRTPReturnEndpointName];
        self.lastTest.stringValue = @"Endpoint interne refusé comme console distante";
        return;
    }

    if (
        self.validatedEndpoint.length &&
        ![self.validatedEndpoint isEqualToString:endpoint]
    ) {
        self.validatedEndpoint = nil;
        self.validatedAt = nil;
        self.lastRTPTestStatus = @"available";
        self.lastRTPTestLatencyMs = nil;
        self.lastRTPTestMessage =
            @"Nouvel endpoint sélectionné · lancez un test aller-retour";
        self.lastRTPTestAt = [NSDate date];
    }

    self.loopDetectedEndpoint = nil;
    [self refreshEndpoints];
}
- (void)returnModeChanged:(id)sender {
    (void)sender;
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 1;
    [NSUserDefaults.standardUserDefaults setObject:(self.localReturnMode ? @"local_dedicated" : @"rtp_remote")
                                            forKey:@"consoleReturnMode"];
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
        self.returnMonitorSource = 0;
    }
    if (self.localReturnMode) {
        self.returnMonitorStatus = self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;
        self.lastTest.stringValue = @"Test local · retour dédié";
    } else {
        [self.endpointMenu selectItemWithTitle:CLRTPReturnEndpointName];
        [self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName];
        self.lastTest.stringValue = @"RTP distant · choisissez la console distante";
    }
    [self refreshEndpoints];
}
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
    NSString *host = self.rtpPeerHosts[peer] ?: @"";
    NSUInteger port = [self.rtpPeerPorts[peer] unsignedIntegerValue];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[@"--peer-name", peer]];
    if (host.length && port > 0) {
        [arguments addObjectsFromArray:@[@"--peer-host", host, @"--peer-port", [NSString stringWithFormat:@"%lu", (unsigned long)port]]];
    }
    [arguments addObjectsFromArray:@[@"--interval", @"2"]];
    task.arguments = arguments;
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
    self.guardianHost = host;
    self.guardianPort = port;
    CLAppendDiagnostic(@"guardian-start", [NSString stringWithFormat:@"peer=%@ host=%@ port=%lu", peer, host.length ? host : @"Bonjour", (unsigned long)port]);
}

- (void)restartGuardianForPeer:(NSString *)peer {
    if (self.guardianTask.running) [self.guardianTask terminate];
    self.guardianTask = nil;
    self.guardianPeer = nil;
    self.guardianHost = nil;
    self.guardianPort = 0;
    [self startGuardianForPeer:peer];
}

- (void)ensureGuardianRunning {
    NSString *peer = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    if (!peer.length) return;
    NSString *host = self.rtpPeerHosts[peer] ?: @"";
    NSUInteger port = [self.rtpPeerPorts[peer] unsignedIntegerValue];
    if (self.guardianTask.running && [self.guardianPeer isEqualToString:peer] &&
        [self.guardianHost ?: @"" isEqualToString:host] && self.guardianPort == port) return;
    [self restartGuardianForPeer:peer];
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
        [self restartGuardianForPeer:selected];
    }
    if (selected.length && [names containsObject:selected] &&
        ![self.systemConnectAttemptedPeers containsObject:selected]) {
        [self connectPeerThroughSystem:selected automatic:YES];
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
    if (!sender.name.length) return;
    if (sender.hostName.length) self.peerHosts[sender.name] = sender.hostName;
    if (![sender.type isEqualToString:@"_apple-midi._udp."]) return;
    NSString *numericHost = nil;
    for (NSData *addressData in sender.addresses) {
        const struct sockaddr *address = addressData.bytes;
        if (!address || address->sa_family != AF_INET) continue;
        char buffer[NI_MAXHOST] = {0};
        if (getnameinfo(address, addressData.length, buffer, sizeof(buffer), NULL, 0, NI_NUMERICHOST) == 0) {
            numericHost = [NSString stringWithUTF8String:buffer];
            break;
        }
    }
    if (!numericHost.length) numericHost = sender.hostName;
    if (numericHost.length) self.rtpPeerHosts[sender.name] = numericHost;
    if (sender.port > 0) self.rtpPeerPorts[sender.name] = @(sender.port);
    NSString *preferred = [NSUserDefaults.standardUserDefaults stringForKey:@"preferredRtpPeer"];
    if ([preferred isEqualToString:sender.name]) [self ensureGuardianRunning];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length && self.peerServices[service.name] == service) {
        [self.discoveredPeers removeObject:service.name];
        [self.peerServices removeObjectForKey:service.name];
        [self.peerHosts removeObjectForKey:service.name];
        if ([service.type isEqualToString:@"_apple-midi._udp."]) {
            [self.rtpPeerHosts removeObjectForKey:service.name];
            [self.rtpPeerPorts removeObjectForKey:service.name];
            [self.systemConnectAttemptedPeers removeObject:service.name];
            [self.systemConnectRetryCounts removeObjectForKey:service.name];
        }
    }
    if (!moreComing) [self refreshTargetMenu];
}

- (void)connectPeerThroughSystem:(NSString *)peer automatic:(BOOL)automatic {
    if (!peer.length || [peer hasPrefix:@"Aucun"] || [peer hasPrefix:@"Recherche"] || self.systemConnectRunning) return;
    if (automatic && [self.systemConnectAttemptedPeers containsObject:peer]) return;
    [self.systemConnectAttemptedPeers addObject:peer];
    self.systemConnectRunning = YES;
    self.connectButton.enabled = NO;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion système vers %@…", peer];
    CLAppendDiagnostic(@"rtp-connect-start", [NSString stringWithFormat:@"peer=%@ method=SystemMIDI double-click", peer]);
    [self restartGuardianForPeer:peer];

    NSString *template = [NSString stringWithContentsOfFile:[self toolPath:@"connect_rtp_peer.applescript"]
                                                    encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *escapedPeer = [[peer stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                              stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *source = [template stringByReplacingOccurrencesOfString:@"__CL_PEER__" withString:escapedPeer];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *scriptError = nil;
        NSAppleEventDescriptor *result = source.length
            ? [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&scriptError]
            : nil;
        NSString *output = result.stringValue ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.systemConnectRunning = NO;
            self.connectButton.enabled = self.discoveredPeers.count > 0;
            BOOL connected = !scriptError && ([output hasPrefix:@"connected:"] || [output hasPrefix:@"already-connected:"]);
            if (connected) {
                [self.systemConnectRetryCounts removeObjectForKey:peer];
                self.lastTest.stringValue = [NSString stringWithFormat:@"✓ %@ connecté par macOS · test MIDI requis", peer];
                CLAppendDiagnostic(@"rtp-connect-success", output);
            } else {
                NSString *reason = scriptError[NSAppleScriptErrorMessage] ?: (output.length ? output : @"connecteur indisponible");
                BOOL postedPhysicalClick = CLPostDoubleClickFromConnectorReason(reason);
                NSUInteger retry = [self.systemConnectRetryCounts[peer] unsignedIntegerValue] + 1;
                self.systemConnectRetryCounts[peer] = @(retry);
                BOOL willRetry = automatic && retry <= 8 && [self.discoveredPeers containsObject:peer];
                self.lastTest.stringValue = willRetry
                    ? [NSString stringWithFormat:@"Connexion en attente · nouvel essai automatique %lu/8", (unsigned long)retry]
                    : [NSString stringWithFormat:@"Connexion système incomplète · %@", reason];
                CLAppendDiagnostic(@"rtp-connect-pending", [NSString stringWithFormat:@"peer=%@ reason=%@", peer, reason]);
                if (postedPhysicalClick) {
                    CLAppendDiagnostic(@"rtp-connect-physical-click", [NSString stringWithFormat:@"peer=%@", peer]);
                }
                if (willRetry) {
                    NSTimeInterval delay = postedPhysicalClick ? 1.0 : MIN(30.0, 5.0 + retry * 3.0);
                    CLAppendDiagnostic(@"rtp-connect-retry-scheduled", [NSString stringWithFormat:@"peer=%@ attempt=%lu delay=%.0f", peer, (unsigned long)retry, delay]);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self.systemConnectAttemptedPeers removeObject:peer];
                        [self connectPeerThroughSystem:peer automatic:YES];
                    });
                }
            }
            [self writeConsoleReturnState];
        });
    });
}

- (void)connectSelectedPeer:(id)sender {
    (void)sender;
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    if (!peer.length || [peer hasPrefix:@"Aucun"] || [peer hasPrefix:@"Recherche"]) return;
    [[NSUserDefaults standardUserDefaults] setObject:peer forKey:@"preferredRtpPeer"];
    [self.systemConnectAttemptedPeers removeObject:peer];
    [self connectPeerThroughSystem:peer automatic:NO];
}

- (void)refreshEndpoints {
    NSArray<NSString *> *sources = EndpointNames(YES);
    NSArray<NSString *> *destinations = EndpointNames(NO);
    NSString *selected = self.endpointMenu.selectedItem.title;
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    for (NSString *name in sources) {
        if (CLIsRTPReturnEndpointName(name)) [candidates addObject:name];
    }
    for (NSString *name in destinations) {
        if (CLIsRTPReturnEndpointName(name)) [candidates addObject:name];
    }
    [self.endpointMenu removeAllItems];
    [self.endpointMenu addItemsWithTitles:candidates.array.count ? candidates.array : @[@"Aucun port MIDI détecté"]];
    if (selected.length && [candidates containsObject:selected]) [self.endpointMenu selectItemWithTitle:selected];
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];

    if (self.simulatorEndpointMenu && self.simulatorModeMenu.indexOfSelectedItem == 1) {
        NSArray<NSString *> *localRTPEndpoints = CLLocalRTPEndpointNames();
        NSString *current = self.simulatorEndpointMenu.titleOfSelectedItem;
        NSString *preferred = [localRTPEndpoints containsObject:current]
            ? current : CLPreferredLocalRTPEndpoint(localRTPEndpoints);
        [self.simulatorEndpointMenu removeAllItems];
        [self.simulatorEndpointMenu addItemsWithTitles:localRTPEndpoints.count
            ? localRTPEndpoints : @[@"Aucun endpoint RTP local détecté"]];
        if (preferred.length) [self.simulatorEndpointMenu selectItemWithTitle:preferred];
        self.simulatorEndpointMenu.enabled = localRTPEndpoints.count > 0;

        NSArray<NSString *> *sources = CLSimulatorInputEndpointNames();
        NSString *savedInput = [NSUserDefaults.standardUserDefaults stringForKey:@"simulatorInputEndpoint"] ?: @"";
        NSString *selectedInput = [sources containsObject:savedInput] ? savedInput : @"Aucune";
        [self.simulatorInputEndpointMenu removeAllItems];
        [self.simulatorInputEndpointMenu addItemWithTitle:@"Aucune"];
        [self.simulatorInputEndpointMenu addItemsWithTitles:sources];
        [self.simulatorInputEndpointMenu selectItemWithTitle:selectedInput];
        self.simulatorInputEndpointMenu.enabled = YES;
    }

    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    // Chaque rôle est reconnecté indépendamment. L'absence d'un endpoint ne
    // doit jamais déconnecter l'autre source encore valide.
    [self selectPassiveExpectedSourceNamed:CLExpectedEndpointName];
    if (!self.localReturnMode) [self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName];
    BOOL hasSource = [sources containsObject:endpoint];
    BOOL hasDestination = [destinations containsObject:endpoint];
    MIDINetworkSession *session = [MIDINetworkSession defaultSession];
    NSString *validation = (self.validatedEndpoint && [self.validatedEndpoint isEqualToString:endpoint])
        ? @"Connexion confirmée par aller-retour MIDI"
        : @"Connexion à confirmer par test MIDI";
    self.technicalSession.stringValue = [NSString stringWithFormat:@"Réglages : gérés par macOS\nIndication API macOS : %lu (peut être incomplète)\n%@",
        (unsigned long)session.connections.count, validation];
    self.technicalEndpoints.stringValue = [NSString stringWithFormat:@"Entrées : %lu   Sorties : %lu\nPorts MIDI détectés : %lu\nCoreMIDI : %@",
        (unsigned long)sources.count, (unsigned long)destinations.count, (unsigned long)candidates.count,
        (sources.count || destinations.count) ? @"opérationnel" : @"aucun port"];
    self.technicalSelection.stringValue = [NSString stringWithFormat:
        @"Source expected Ableton (indépendante du RTP) : %@ · %@\nSource console / retour RTP : %@ · %@",
        CLExpectedEndpointName, self.expectedMonitorSource ? @"connectée" : @"indisponible (sans effet sur la liaison RTP)",
        self.localReturnMode ? CLLocalReturnEndpointName : CLRTPReturnEndpointName,
        self.localReturnMode ? (self.localReturnDestination ? @"connectée" : @"indisponible") :
            (self.returnMonitorSource ? @"connectée" : @"indisponible")];
    if (self.showModeEnabled) [self updateCompactSummary];

    [self updateRoundTripPanelForCurrentMode];
    if (self.localReturnMode) {
        [self setLamp:
            self.localReturnDestination ? [NSColor systemGreenColor] : [NSColor systemOrangeColor]
            title:@"RETOUR LOCAL DÉDIÉ"
            detail:self.localReturnDestination
                ? @"Expected et returned sont observés passivement sur leurs ports dédiés."
                : @"Le port CL MIDI Return Test est indisponible."];
    } else if (self.loopDetectedEndpoint && [self.loopDetectedEndpoint isEqualToString:endpoint]) {
        [self setLamp:[NSColor systemRedColor] title:@"BOUCLE MIDI DÉTECTÉE" detail:@"Dans Ableton : désactivez Entrée RTP > Piste, puis relancez le test."];
    } else if (
        [self.lastRTPTestStatus isEqualToString:@"validated"] &&
        self.validatedEndpoint &&
        [self.validatedEndpoint isEqualToString:endpoint]
    ) {
        NSTimeInterval age =
            self.validatedAt
                ? MAX(0.0, -[self.validatedAt timeIntervalSinceNow])
                : 0.0;

        NSString *latency =
            self.lastRTPTestLatencyMs
                ? [NSString stringWithFormat:@" · %.1f ms",
                    self.lastRTPTestLatencyMs.doubleValue]
                : @"";

        [self setLamp:
            [NSColor systemGreenColor]
            title:@"RTP VALIDÉ"
            detail:[NSString stringWithFormat:
                @"Aller-retour confirmé il y a %.0f s sur %@%@",
                age,
                endpoint,
                latency]];

    } else if ([self.lastRTPTestStatus isEqualToString:@"running"]) {
        [self setLamp:
            [NSColor systemOrangeColor]
            title:@"TEST RTP EN COURS"
            detail:self.lastRTPTestMessage ?: @"Vérification aller-retour…"];

    } else if ([self.lastRTPTestStatus isEqualToString:@"loop_detected"]) {
        [self setLamp:
            [NSColor systemRedColor]
            title:@"BOUCLE MIDI"
            detail:self.lastRTPTestMessage ?: @"Boucle MIDI détectée"];

    } else if (
        [self.lastRTPTestStatus isEqualToString:@"timeout"] ||
        [self.lastRTPTestStatus isEqualToString:@"send_error"] ||
        [self.lastRTPTestStatus isEqualToString:@"failed"]
    ) {
        [self setLamp:
            [NSColor systemRedColor]
            title:@"RTP NON VALIDÉ"
            detail:self.lastRTPTestMessage ?: @"Le dernier test a échoué"];

    } else if (hasSource && hasDestination) {
        [self setLamp:
            [NSColor systemOrangeColor]
            title:@"RTP DISPONIBLE"
            detail:@"Ports visibles · lancez un test aller-retour"];

    } else {
        [self setLamp:
            [NSColor systemRedColor]
            title:@"RTP HORS LIGNE"
            detail:@"Aucune paire entrée/sortie RTP exploitable n’est visible."];
    }
    [self writeConsoleReturnState];
}

- (NSString *)toolPath:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *resourcePath = [NSBundle mainBundle].resourcePath;
    if (resourcePath.length) {
        NSString *bundled = [resourcePath stringByAppendingPathComponent:
            [@"Network Tools" stringByAppendingPathComponent:name]];
        if ([fm isExecutableFileAtPath:bundled]) return bundled;
    }

    NSString *executablePath = [NSBundle mainBundle].executablePath;
    if (executablePath.length) {
        NSString *sibling = [[executablePath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:sibling]) return sibling;
    }

    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length) {
        NSString *buildTool = [[cwd stringByAppendingPathComponent:@"build"]
            stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:buildTool]) return buildTool;

        NSString *direct = [cwd stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:direct]) return direct;
    }

    return resourcePath.length
        ? [resourcePath stringByAppendingPathComponent:
            [@"Network Tools" stringByAppendingPathComponent:name]]
        : name;
}

- (void)runTest:(id)sender {
    (void)sender;
    if (self.localReturnMode) {
        // Le mode local repose exclusivement sur les moniteurs expected/returned
        // dédiés. Il ne doit jamais lancer l'ancien aller-retour générique.
        return;
    }
    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    if ([endpoint isEqualToString:CLExpectedEndpointName] || [endpoint isEqualToString:CLLocalReturnEndpointName]) {
        self.lastTest.stringValue = @"Diagnostic RTP refusé sur un endpoint interne";
        return;
    }
    NSInteger program = self.programField.integerValue;
    NSInteger channel = self.testTargetMenu.indexOfSelectedItem + 1;
    NSString *console = channel == 2 ? @"QL1" : @"CL5";
    if ([endpoint hasPrefix:@"Aucun"] || program < 1 || program > 128) {
        self.lastTest.stringValue = @"Sélection ou Program Change invalide";
        return;
    }
    self.testButton.enabled = NO;
    self.lastRTPTestStatus = @"running";
    self.lastRTPTestLatencyMs = nil;
    self.lastRTPTestAt = [NSDate date];
    self.lastRTPTestMessage =
        [NSString stringWithFormat:@"Test %@ · canal %ld · PGM %ld…",
            console, (long)channel, (long)program];
    self.lastTest.stringValue = self.lastRTPTestMessage;
    [self writeConsoleReturnState];
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
            CLAppendDiagnostic(@"round-trip-result", [NSString stringWithFormat:@"endpoint=%@ channel=%ld program=%ld exit=%d output=%@",
                endpoint, (long)channel, (long)program, finished.terminationStatus, output]);
            if (finished.terminationStatus == 0) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"latency_ms=([0-9.]+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
                NSString *latency = match ? [output substringWithRange:[match rangeAtIndex:1]] : @"?";
                self.validatedEndpoint = endpoint;
                self.loopDetectedEndpoint = nil;
                self.validatedAt = [NSDate date];
                self.lastRTPTestStatus = @"validated";
                self.lastRTPTestLatencyMs = @([latency doubleValue]);
                self.lastRTPTestAt = self.validatedAt;
                self.lastRTPTestMessage =
                    [NSString stringWithFormat:
                        @"✓ %@ · canal %ld · PGM %ld confirmé · %@ ms",
                        console, (long)channel, (long)program, latency];
                self.lastTest.stringValue = self.lastRTPTestMessage;
                NSString *compactResult = [NSString stringWithFormat:@"PGM %ld confirmé · %@ ms", (long)program, latency];
                if (channel == 1) self.lastCL5Test = compactResult; else self.lastQL1Test = compactResult;
            } else {
                self.validatedEndpoint = nil;
                BOOL loopDetected = [output rangeOfString:@"LOOP_DETECTED"].location != NSNotFound;
                if (loopDetected) self.loopDetectedEndpoint = endpoint;
                NSString *reason = loopDetected ? @"boucle MIDI détectée · désactivez Entrée RTP > Piste dans Ableton"
                    : ([output rangeOfString:@"TIMEOUT"].location != NSNotFound ? @"envoi RTP réussi · aucun simulateur de retour actif sur le Mac distant"
                    : ([output rangeOfString:@"COREMIDI_CLIENT_ERROR"].location != NSNotFound ? @"CoreMIDI indisponible"
                    : ([output rangeOfString:@"RTP_ENDPOINTS_NOT_FOUND"].location != NSNotFound ? @"port RTP introuvable"
                    : ([output rangeOfString:@"COREMIDI_SEND_ERROR"].location != NSNotFound ? @"envoi CoreMIDI refusé" : @"test impossible"))));
                self.lastRTPTestStatus =
                    loopDetected
                        ? @"loop_detected"
                        : ([output rangeOfString:@"TIMEOUT"].location != NSNotFound
                            ? @"timeout"
                            : ([output rangeOfString:@"COREMIDI_SEND_ERROR"].location != NSNotFound
                                ? @"send_error"
                                : @"failed"));
                self.lastRTPTestLatencyMs = nil;
                self.lastRTPTestAt = [NSDate date];
                self.lastRTPTestMessage =
                    [NSString stringWithFormat:@"Échec : %@", reason];
                self.lastTest.stringValue = self.lastRTPTestMessage;
                if (channel == 1) self.lastCL5Test = reason; else self.lastQL1Test = reason;
            }
            if (self.showModeEnabled) [self updateCompactSummary];
            [self writeConsoleReturnState];
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
    CLAppendDiagnostic(@"midi-settings-open", @"manual request");
    NSString *source = [NSString stringWithContentsOfFile:[self toolPath:@"open_rtp_settings.applescript"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (error) self.lastTest.stringValue = @"Impossible d’ouvrir directement les réglages RTP. Vérifiez l’autorisation Accessibilité.";
    else [self inspectMidiDirectory];
}

- (NSDictionary *)sendSimulatorAction:(NSString *)action host:(NSString *)host {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
        if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        struct addrinfo hints = {0}, *results = NULL;
        hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM;
        int lookup = getaddrinfo(host.UTF8String, "50022", &hints, &results);
        NSDictionary *command = @{@"service": @"cl-midi-rtp-control", @"action": action};
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
        ssize_t sent = (lookup == 0 && fd >= 0) ? sendto(fd, encoded.bytes, encoded.length, 0, results->ai_addr, results->ai_addrlen) : -1;
        UInt8 buffer[2048]; ssize_t received = sent >= 0 ? recv(fd, buffer, sizeof(buffer), 0) : -1;
        NSDictionary *reply = received > 0 ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:(NSUInteger)received] options:0 error:nil] : nil;
        if (results) freeaddrinfo(results); if (fd >= 0) close(fd);
        return reply;
}

- (void)showSimulatorMessage:(NSString *)message title:(NSString *)title {
    self.lastTest.stringValue = message;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)startSimulator:(id)sender {
    (void)sender;
    self.showModeEnabled = NO;
    [self applyPresentationMode];
}

- (NSArray<NSString *> *)allMidiEndpointNames {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    [names addObjectsFromArray:EndpointNames(YES)];
    [names addObjectsFromArray:EndpointNames(NO)];
    return names.array;
}

static NSString * const CLSimulatorDevicesDefaultsKey = @"CLSimulatorDevicesV1";

- (NSMutableDictionary *)simulatorDeviceWithID:(NSString *)deviceID name:(NSString *)name channel:(NSInteger)channel enabled:(BOOL)enabled builtIn:(BOOL)builtIn {
    return [@{
        @"id": deviceID,
        @"name": name,
        @"channel": @(channel),
        @"enabled": @(enabled),
        @"built_in": @(builtIn),
        @"last_program": NSNull.null,
        @"last_event_at": NSNull.null,
        @"last_title": @"",
        @"event_history": [NSMutableArray array],
    } mutableCopy];
}

- (void)loadSimulatorDevices {
    self.simulatorDevices = [NSMutableArray array];
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:CLSimulatorDevicesDefaultsKey];
    for (NSDictionary *item in saved ?: @[]) {
        NSString *deviceID = [item[@"id"] isKindOfClass:NSString.class] ? item[@"id"] : @"";
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? [item[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        NSInteger channel = [item[@"channel"] integerValue];
        if (!deviceID.length || !name.length || channel < 1 || channel > 16) continue;
        BOOL builtIn = [deviceID isEqualToString:@"cl5"] || [deviceID isEqualToString:@"ql1"];
        if ([deviceID isEqualToString:@"cl5"]) { name = @"CL5"; channel = 1; }
        if ([deviceID isEqualToString:@"ql1"]) { name = @"QL1"; channel = 2; }
        [self.simulatorDevices addObject:[self simulatorDeviceWithID:deviceID name:name channel:channel enabled:[item[@"enabled"] boolValue] builtIn:builtIn]];
    }
    BOOL hasCL5 = NO, hasQL1 = NO;
    for (NSDictionary *device in self.simulatorDevices) {
        hasCL5 |= [device[@"id"] isEqualToString:@"cl5"];
        hasQL1 |= [device[@"id"] isEqualToString:@"ql1"];
    }
    if (!hasCL5) [self.simulatorDevices insertObject:[self simulatorDeviceWithID:@"cl5" name:@"CL5" channel:1 enabled:YES builtIn:YES] atIndex:0];
    if (!hasQL1) [self.simulatorDevices insertObject:[self simulatorDeviceWithID:@"ql1" name:@"QL1" channel:2 enabled:YES builtIn:YES] atIndex:MIN(1, self.simulatorDevices.count)];
    self.simulatorTasks = [NSMutableDictionary dictionary];
    self.simulatorOutputBuffers = [NSMutableDictionary dictionary];
    [self persistSimulatorDevices];
}

- (void)persistSimulatorDevices {
    NSMutableArray *saved = [NSMutableArray array];
    for (NSDictionary *device in self.simulatorDevices) {
        [saved addObject:@{
            @"id": device[@"id"], @"name": device[@"name"],
            @"channel": device[@"channel"], @"enabled": device[@"enabled"],
        }];
    }
    [NSUserDefaults.standardUserDefaults setObject:saved forKey:CLSimulatorDevicesDefaultsKey];
}

- (NSMutableDictionary *)simulatorDeviceForID:(NSString *)deviceID {
    for (NSMutableDictionary *device in self.simulatorDevices) {
        if ([device[@"id"] isEqualToString:deviceID]) return device;
    }
    return nil;
}

- (NSString *)channelCollisionForChannel:(NSInteger)channel excludingID:(NSString *)excludedID {
    for (NSDictionary *device in self.simulatorDevices) {
        if (![device[@"id"] isEqualToString:excludedID] && [device[@"channel"] integerValue] == channel) {
            return device[@"name"];
        }
    }
    return nil;
}

- (void)updateSimulatorSafetyStatus {
    NSUInteger running = 0;
    for (NSTask *task in self.simulatorTasks.allValues) if (task.running) running += 1;
    if (running) {
        self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"Simulation active · %lu device%@", (unsigned long)running, running > 1 ? @"s" : @""];
        self.simulatorStatusLabel.textColor = [NSColor colorWithRed:1.0 green:0.62 blue:0.25 alpha:1.0];
        self.footerLabel.stringValue = [NSString stringWithFormat:@"Simulation active · %lu device%@", (unsigned long)running, running > 1 ? @"s" : @""];
        self.footerLabel.textColor = [NSColor colorWithRed:1.0 green:0.62 blue:0.25 alpha:1.0];
    } else {
        self.simulatorStatusLabel.stringValue = @"Simulation désactivée · mode spectacle sûr";
        self.simulatorStatusLabel.textColor = [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0];
        self.footerLabel.stringValue = @"CL AUDIO · MIDI NETWORK · 2026";
        self.footerLabel.textColor = [NSColor colorWithWhite:0.38 alpha:1.0];
    }
}

- (NSString *)simulatorSceneTitleForProgram:(NSInteger)program channel:(NSInteger)channel {
    NSDictionary *state = channel == 1 ? self.expectedCL5State : (channel == 2 ? self.expectedQL1State : nil);
    id returnedValue = state[@"returned_midi_program"];
    NSString *title = [state[@"returned_title"] isKindOfClass:NSString.class] ? state[@"returned_title"] : nil;
    if (returnedValue && returnedValue != NSNull.null && [returnedValue integerValue] == program && title.length) return title;
    return @"Titre non résolu";
}

- (void)rebuildSimulatorDeviceRows {
    if (!self.simulatorDeviceRows) { [self updateSimulatorSafetyStatus]; return; }
    for (NSView *view in self.simulatorDeviceRows.arrangedSubviews.copy) [self.simulatorDeviceRows removeArrangedSubview:view], [view removeFromSuperview];
    for (NSDictionary *device in self.simulatorDevices) {
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 610, 68)];
        row.wantsLayer = YES; row.layer.cornerRadius = 7; row.layer.backgroundColor = [NSColor colorWithWhite:0.09 alpha:1.0].CGColor;
        NSButton *enabled = [[NSButton alloc] initWithFrame:NSMakeRect(8, 22, 22, 24)];
        enabled.buttonType = NSButtonTypeSwitch; enabled.state = [device[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        enabled.identifier = device[@"id"]; enabled.target = self; enabled.action = @selector(toggleSimulatorDeviceEnabled:); [row addSubview:enabled];
        NSInteger channel = [device[@"channel"] integerValue];
        NSTextField *name = [self label:device[@"name"] frame:NSMakeRect(36, 42, 145, 18) size:12 bold:YES]; [row addSubview:name];
        NSTextField *detail = [self label:[NSString stringWithFormat:@"Canal %ld", (long)channel] frame:NSMakeRect(36, 23, 145, 16) size:9 bold:NO]; [row addSubview:detail];
        id lastProgram = device[@"last_program"];
        NSDate *lastAt = [device[@"last_event_at"] isKindOfClass:NSDate.class] ? device[@"last_event_at"] : nil;
        NSString *event = @"Aucun Program Change reçu";
        NSString *scene = @"En attente du retour MIDI";
        if (lastProgram != NSNull.null && lastAt) {
            NSDateFormatter *clock = [[NSDateFormatter alloc] init]; clock.dateFormat = @"HH:mm:ss";
            event = [NSString stringWithFormat:@"PGM %ld · %@ · %@", (long)[lastProgram integerValue] + 1, [clock stringFromDate:lastAt], CLMidiAgeDescription(-lastAt.timeIntervalSinceNow)];
            scene = [self simulatorSceneTitleForProgram:[lastProgram integerValue] channel:channel];
        }
        NSTextField *sceneLabel = [self label:scene frame:NSMakeRect(184, 39, 245, 18) size:10 bold:YES]; sceneLabel.lineBreakMode = NSLineBreakByTruncatingTail; [row addSubview:sceneLabel];
        NSTextField *eventLabel = [self label:event frame:NSMakeRect(184, 18, 300, 18) size:9 bold:NO]; eventLabel.lineBreakMode = NSLineBreakByTruncatingTail; [row addSubview:eventLabel];
        NSString *state = self.simulatorTasks[device[@"id"]].running ? @"ACTIF" : @"arrêté";
        [row addSubview:[self label:state frame:NSMakeRect(36, 5, 145, 16) size:8 bold:YES]];
        NSButton *startStop = [self button:self.simulatorTasks[device[@"id"]].running ? @"■" : @"▶" frame:NSMakeRect(494, 20, 32, 28) action:@selector(toggleSimulatorDeviceRunning:)]; startStop.toolTip = self.simulatorTasks[device[@"id"]].running ? @"Arrêter" : @"Démarrer"; startStop.identifier = device[@"id"]; [row addSubview:startStop];
        NSButton *edit = [self button:@"✎" frame:NSMakeRect(532, 20, 32, 28) action:@selector(editSimulatorDevice:)]; edit.toolTip = @"Modifier"; edit.identifier = device[@"id"]; edit.enabled = ![device[@"built_in"] boolValue]; [row addSubview:edit];
        if (![device[@"built_in"] boolValue]) { NSButton *remove = [self button:@"×" frame:NSMakeRect(570, 20, 32, 28) action:@selector(deleteSimulatorDevice:)]; remove.toolTip = @"Supprimer"; remove.identifier = device[@"id"]; [row addSubview:remove]; }
        [self.simulatorDeviceRows addArrangedSubview:row];
        [row.widthAnchor constraintEqualToConstant:610].active = YES; [row.heightAnchor constraintEqualToConstant:68].active = YES;
    }
    [self updateSimulatorSafetyStatus];
}

- (void)createIntegratedSimulatorPanelInView:(NSView *)parent {
    [self loadSimulatorDevices];
    self.simulatorTasks = [NSMutableDictionary dictionary];
    self.simulatorOutputBuffers = [NSMutableDictionary dictionary];
    NSView *content = self.simulatorPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 183, 468, 190)];
    content.wantsLayer = YES; content.layer.cornerRadius = 12; content.layer.borderWidth = 1;
    content.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.060 blue:0.045 alpha:1.0].CGColor;
    content.layer.borderColor = [NSColor colorWithRed:0.72 green:0.43 blue:0.18 alpha:0.72].CGColor;
    [parent addSubview:content];

    NSTextField *title = [self label:@"SIMULATEUR DE RETOUR CONSOLE" frame:NSMakeRect(14, 160, 280, 20) size:11 bold:YES];
    title.textColor = [NSColor colorWithRed:1.0 green:0.68 blue:0.28 alpha:1.0];
    [content addSubview:title];
    [content addSubview:[self button:@"Afficher les détails" frame:NSMakeRect(326, 156, 128, 26) action:@selector(toggleShowMode:)]];

    [content addSubview:[self label:@"MODE" frame:NSMakeRect(14, 146, 80, 18) size:8 bold:YES]];
    self.simulatorModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, 122, 140, 28) pullsDown:NO];
    [self.simulatorModeMenu addItemsWithTitles:@[@"Test local · retour dédié", @"Test distant · RTP"]];
    self.simulatorModeMenu.target = self;
    self.simulatorModeMenu.action = @selector(simulatorModeChanged:);
    [self stylePopup:self.simulatorModeMenu accent:[NSColor colorWithRed:0.92 green:0.58 blue:0.26 alpha:1.0]];
    [content addSubview:self.simulatorModeMenu];

    self.simulatorEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(160, 122, 140, 28) pullsDown:NO];
    [self.simulatorEndpointMenu addItemWithTitle:CLLocalReturnEndpointName];
    self.simulatorEndpointMenu.target = self;
    self.simulatorEndpointMenu.action = @selector(simulatorEndpointChanged:);
    [self stylePopup:self.simulatorEndpointMenu accent:[NSColor colorWithRed:0.44 green:0.76 blue:1.0 alpha:1.0]];
    [content addSubview:self.simulatorEndpointMenu];
    [content addSubview:[self label:@"DESTINATION RTP" frame:NSMakeRect(164, 148, 120, 14) size:8 bold:YES]];

    [content addSubview:[self label:@"SOURCE AUTOMATIQUE" frame:NSMakeRect(310, 148, 144, 14) size:8 bold:YES]];
    self.simulatorInputEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(306, 122, 148, 28) pullsDown:NO];
    [self.simulatorInputEndpointMenu addItemWithTitle:@"Aucune"];
    self.simulatorInputEndpointMenu.target = self;
    self.simulatorInputEndpointMenu.action = @selector(simulatorInputEndpointChanged:);
    [self stylePopup:self.simulatorInputEndpointMenu accent:[NSColor colorWithRed:0.62 green:0.62 blue:0.68 alpha:1.0]];
    [content addSubview:self.simulatorInputEndpointMenu];

    [content addSubview:[self label:@"CL5 · Canal MIDI 1 · Mémoire" frame:NSMakeRect(14, 94, 204, 20) size:10 bold:YES]];
    self.simulatorCL5MemoryField = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 90, 54, 26)];
    self.simulatorCL5MemoryField.stringValue = @"81"; self.simulatorCL5MemoryField.alignment = NSTextAlignmentCenter; [content addSubview:self.simulatorCL5MemoryField];
    NSButton *sendCL5 = [self accentButton:@"Envoyer" frame:NSMakeRect(282, 89, 80, 28) action:@selector(sendSimulatorMemory:) color:[NSColor colorWithRed:0.18 green:0.46 blue:0.72 alpha:1.0]];
    sendCL5.tag = 1; [content addSubview:sendCL5];
    [content addSubview:[self label:@"QL1 · Canal MIDI 2 · Mémoire" frame:NSMakeRect(14, 62, 204, 20) size:10 bold:YES]];
    self.simulatorQL1MemoryField = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 58, 54, 26)];
    self.simulatorQL1MemoryField.stringValue = @"78"; self.simulatorQL1MemoryField.alignment = NSTextAlignmentCenter; [content addSubview:self.simulatorQL1MemoryField];
    NSButton *sendQL1 = [self accentButton:@"Envoyer" frame:NSMakeRect(282, 57, 80, 28) action:@selector(sendSimulatorMemory:) color:[NSColor colorWithRed:0.18 green:0.46 blue:0.72 alpha:1.0]];
    sendQL1.tag = 2; [content addSubview:sendQL1];

    self.simulatorDelayField = [[NSTextField alloc] initWithFrame:NSMakeRect(372, 89, 42, 26)];
    self.simulatorDelayField.stringValue = @"80";
    self.simulatorDelayField.alignment = NSTextAlignmentCenter;
    [content addSubview:self.simulatorDelayField];
    [content addSubview:[self label:@"ms" frame:NSMakeRect(417, 94, 28, 18) size:8 bold:NO]];
    [content addSubview:[self accentButton:@"ACTIVER TEST" frame:NSMakeRect(14, 20, 126, 30) action:@selector(startIntegratedSimulator:) color:[NSColor colorWithRed:0.10 green:0.56 blue:0.31 alpha:1.0]]];
    [content addSubview:[self accentButton:@"ARRÊTER TOUT" frame:NSMakeRect(148, 20, 118, 30) action:@selector(stopIntegratedSimulator:) color:[NSColor colorWithRed:0.58 green:0.18 blue:0.20 alpha:1.0]]];
    self.simulatorStatusLabel = [self label:@"Simulation désactivée" frame:NSMakeRect(276, 22, 178, 24) size:9 bold:YES];
    self.simulatorStatusLabel.alignment = NSTextAlignmentRight;
    self.simulatorStatusLabel.textColor = [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0];
    [content addSubview:self.simulatorStatusLabel];
    [self simulatorModeChanged:nil];
}

- (void)sendSimulatorMemory:(NSButton *)sender {
    NSInteger channel = sender.tag;
    NSTextField *field = channel == 1 ? self.simulatorCL5MemoryField : self.simulatorQL1MemoryField;
    NSInteger sceneMemory = field.integerValue;
    if (sceneMemory < 1 || sceneMemory > 128) {
        self.simulatorStatusLabel.stringValue = @"Mémoire invalide · plage 1 à 128";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return;
    }
    NSString *endpoint = self.localReturnMode ? CLExpectedEndpointName : self.simulatorEndpointMenu.titleOfSelectedItem;
    if (!self.localReturnMode && ![CLLocalRTPEndpointNames() containsObject:endpoint]) {
        self.simulatorStatusLabel.stringValue = @"Endpoint RTP local introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    if (self.localReturnMode) {
        task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLMIDIRoundTripTester"]];
        task.arguments = @[@"--endpoint", endpoint, @"--program", [NSString stringWithFormat:@"%ld", (long)sceneMemory],
                           @"--channel", [NSString stringWithFormat:@"%ld", (long)channel], @"--timeout", @"0.2"];
    } else {
        task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLYamahaConsoleSimulator"]];
        task.arguments = @[@"--label", channel == 1 ? @"CL5" : @"QL1",
                           @"--channel", [NSString stringWithFormat:@"%ld", (long)channel],
                           @"--transport", @"rtp", @"--endpoint", endpoint,
                           @"--send-program", [NSString stringWithFormat:@"%ld", (long)sceneMemory], @"--no-echo"];
    }
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"Envoi impossible : %@", error.localizedDescription];
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return;
    }
    self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"%@ · mémoire %ld envoyée", channel == 1 ? @"CL5" : @"QL1", (long)sceneMemory];
    self.simulatorStatusLabel.textColor = [NSColor colorWithRed:1.0 green:0.68 blue:0.28 alpha:1.0];
    CLAppendDiagnostic(@"integrated-simulator-manual-send", [NSString stringWithFormat:@"channel=%ld memory=%ld endpoint=%@", (long)channel, (long)sceneMemory, endpoint]);
}

- (void)simulatorModeChanged:(id)sender {
    (void)sender;
    NSInteger mode = self.simulatorModeMenu.indexOfSelectedItem;
    self.localReturnMode = mode == 0;
    [self updateRoundTripPanelForCurrentMode];
    if (self.localReturnMode) {
        [self.simulatorEndpointMenu removeAllItems];
        [self.simulatorEndpointMenu addItemWithTitle:CLLocalReturnEndpointName];
        self.simulatorEndpointMenu.enabled = NO;
        [self.simulatorInputEndpointMenu removeAllItems];
        if ([CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName]) {
            [self.simulatorInputEndpointMenu addItemWithTitle:CLExpectedEndpointName];
        } else {
            [self.simulatorInputEndpointMenu addItemWithTitle:@"Aucune"];
        }
        self.simulatorInputEndpointMenu.enabled = NO;
    }
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
        self.returnMonitorSource = 0;
    }
    if (self.localReturnMode) self.returnMonitorStatus = self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;
    else [self selectPassiveReturnSourceNamed:CLRTPReturnEndpointName];
    if (!self.localReturnMode) [self.endpointMenu selectItemWithTitle:CLRTPReturnEndpointName];
    [self refreshEndpoints];
}

- (void)simulatorEndpointChanged:(id)sender {
    (void)sender;
    NSString *endpoint = self.simulatorEndpointMenu.titleOfSelectedItem ?: @"";
    if ([CLLocalRTPEndpointNames() containsObject:endpoint]) {
        [NSUserDefaults.standardUserDefaults setObject:endpoint forKey:@"simulatorLocalRtpEndpoint"];
    }
}

- (void)simulatorInputEndpointChanged:(id)sender {
    (void)sender;
    NSString *input = self.simulatorInputEndpointMenu.titleOfSelectedItem ?: @"Aucune";
    if ([input isEqualToString:@"Aucune"]) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"simulatorInputEndpoint"];
    else [NSUserDefaults.standardUserDefaults setObject:input forKey:@"simulatorInputEndpoint"];
}

- (NSTask *)launchSimulatorDevice:(NSMutableDictionary *)device transport:(NSString *)transport endpoint:(NSString *)endpoint delay:(NSInteger)delay {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLYamahaConsoleSimulator"]];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:
        @[@"--label", device[@"name"], @"--channel", [device[@"channel"] stringValue], @"--transport", transport,
          @"--endpoint", endpoint ?: @"", @"--delay-ms", [NSString stringWithFormat:@"%ld", (long)delay]]];
    NSString *input = self.localReturnMode ?
        ([CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName] ? CLExpectedEndpointName : @"") :
        self.simulatorInputEndpointMenu.titleOfSelectedItem;
    if (input.length && ![input isEqualToString:@"Aucune"]) {
        [arguments addObjectsFromArray:@[@"--input-endpoint", input]];
    }
    task.arguments = arguments;
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSString *deviceID = device[@"id"];
    self.simulatorOutputBuffers[deviceID] = [NSMutableData data];
    __weak typeof(self) weakSelf = self;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        if (!chunk.length) { handle.readabilityHandler = nil; return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            NSMutableData *buffer = strongSelf.simulatorOutputBuffers[deviceID];
            if (!strongSelf || !buffer) return;
            [buffer appendData:chunk];
            NSString *text = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
            if (!text) return;
            NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
            [buffer setData:[lines.lastObject dataUsingEncoding:NSUTF8StringEncoding]];
            for (NSUInteger index = 0; index + 1 < lines.count; index++) {
                NSString *line = lines[index];
                if (![line hasPrefix:@"RECEIVED "] && ![line hasPrefix:@"CONFIRMED "]) continue;
                NSRange range = [line rangeOfString:@"program="];
                if (range.location == NSNotFound) continue;
                NSInteger midiProgram = [[line substringFromIndex:NSMaxRange(range)] integerValue];
                if (midiProgram >= 0 && midiProgram <= 127) [strongSelf recordSimulatorProgram:midiProgram deviceID:deviceID];
            }
        });
    };
    task.terminationHandler = ^(NSTask *finished) {
        (void)finished;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.simulatorTasks[deviceID] == task) [self.simulatorTasks removeObjectForKey:deviceID];
            [self.simulatorOutputBuffers removeObjectForKey:deviceID];
            [self rebuildSimulatorDeviceRows];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"Échec %@ : %@", device[@"name"], error.localizedDescription];
        return nil;
    }
    self.simulatorTasks[deviceID] = task;
    return task;
}

- (BOOL)simulatorTransport:(NSString **)transport endpoint:(NSString **)endpoint delay:(NSInteger *)delay {
    NSInteger mode = self.simulatorModeMenu.indexOfSelectedItem;
    NSString *selectedEndpoint = self.simulatorEndpointMenu.titleOfSelectedItem ?: @"";
    if ([selectedEndpoint isEqualToString:CLExpectedEndpointName]) {
        self.simulatorStatusLabel.stringValue = @"Retour simulé refusé · Gestionnaire IAC Bus 1 est exclusivement la source expected";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    NSString *requiredEndpoint = mode == 0 ? CLLocalReturnEndpointName : selectedEndpoint;
    if (mode == 1 && ![CLLocalRTPEndpointNames() containsObject:requiredEndpoint]) {
        self.simulatorStatusLabel.stringValue = @"Endpoint RTP local introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    if (mode == 1) {
        NSString *input = self.simulatorInputEndpointMenu.titleOfSelectedItem ?: @"Aucune";
        if (![input isEqualToString:@"Aucune"] && ![CLSimulatorInputEndpointNames() containsObject:input]) {
            [self.simulatorInputEndpointMenu selectItemWithTitle:@"Aucune"];
            self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"Source automatique indisponible : %@ · envoi manuel RTP disponible", input];
        }
        [NSUserDefaults.standardUserDefaults setObject:requiredEndpoint forKey:@"simulatorLocalRtpEndpoint"];
    }
    if (transport) *transport = mode == 0 ? @"iac" : @"rtp";
    if (endpoint) *endpoint = requiredEndpoint;
    if (delay) *delay = MAX(0, self.simulatorDelayField.integerValue);
    return YES;
}

- (void)startSimulatorDevice:(NSMutableDictionary *)device {
    if (!device || self.simulatorTasks[device[@"id"]].running) return;
    NSString *transport, *endpoint; NSInteger delay;
    if (![self simulatorTransport:&transport endpoint:&endpoint delay:&delay]) return;
    [self launchSimulatorDevice:device transport:transport endpoint:endpoint delay:delay];
    [self rebuildSimulatorDeviceRows];
}

- (void)stopSimulatorDeviceID:(NSString *)deviceID {
    NSTask *task = self.simulatorTasks[deviceID];
    if (task.running) [task terminate];
    [self.simulatorTasks removeObjectForKey:deviceID];
    [self rebuildSimulatorDeviceRows];
}

- (void)startIntegratedSimulator:(id)sender {
    (void)sender;
    [self stopIntegratedSimulator:nil];
    NSString *transport, *endpoint; NSInteger delay;
    if (![self simulatorTransport:&transport endpoint:&endpoint delay:&delay]) return;
    for (NSMutableDictionary *device in self.simulatorDevices) if ([device[@"enabled"] boolValue]) [self launchSimulatorDevice:device transport:transport endpoint:endpoint delay:delay];
    [self rebuildSimulatorDeviceRows];
    CLAppendDiagnostic(@"integrated-simulator-started", [NSString stringWithFormat:@"devices=%lu mode=%@ endpoint=%@ delay=%ld", (unsigned long)self.simulatorTasks.count, transport, endpoint, (long)delay]);
}

- (void)stopIntegratedSimulator:(id)sender {
    (void)sender;
    NSArray *tasks = self.simulatorTasks.allValues.copy;
    [self.simulatorTasks removeAllObjects];
    for (NSTask *task in tasks) if (task.running) [task terminate];
    [self rebuildSimulatorDeviceRows];
    CLAppendDiagnostic(@"integrated-simulator-stopped", @"all local simulator tasks stopped");
}

- (void)toggleSimulatorDeviceEnabled:(NSButton *)sender {
    NSMutableDictionary *device = [self simulatorDeviceForID:sender.identifier];
    device[@"enabled"] = @(sender.state == NSControlStateValueOn); [self persistSimulatorDevices];
    if (![device[@"enabled"] boolValue]) [self stopSimulatorDeviceID:device[@"id"]];
}

- (void)toggleSimulatorDeviceRunning:(NSButton *)sender {
    NSString *deviceID = sender.identifier; NSMutableDictionary *device = [self simulatorDeviceForID:deviceID];
    if (self.simulatorTasks[deviceID].running) [self stopSimulatorDeviceID:deviceID]; else [self startSimulatorDevice:device];
}

- (BOOL)editDevice:(NSMutableDictionary *)device title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = title;
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 70)];
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 40, 300, 24)]; name.placeholderString = @"Nom du device"; name.stringValue = device[@"name"] ?: @""; [form addSubview:name];
    NSTextField *channel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 100, 24)]; channel.placeholderString = @"Canal 1–16"; channel.stringValue = [device[@"channel"] stringValue] ?: @"1"; [form addSubview:channel];
    alert.accessoryView = form; [alert addButtonWithTitle:@"Enregistrer"]; [alert addButtonWithTitle:@"Annuler"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    NSString *cleanName = [name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSInteger midiChannel = channel.integerValue;
    if (!cleanName.length || midiChannel < 1 || midiChannel > 16) { [self showSimulatorMessage:@"Le nom est obligatoire et le canal doit être compris entre 1 et 16." title:@"Device invalide"]; return NO; }
    NSString *collision = [self channelCollisionForChannel:midiChannel excludingID:device[@"id"]];
    if (collision.length) { NSAlert *warning = [[NSAlert alloc] init]; warning.messageText = [NSString stringWithFormat:@"⚠ Canal déjà utilisé par %@", collision]; warning.informativeText = @"Ce doublon est autorisé uniquement pour les tests avancés."; [warning addButtonWithTitle:@"Continuer"]; [warning addButtonWithTitle:@"Annuler"]; if ([warning runModal] != NSAlertFirstButtonReturn) return NO; }
    device[@"name"] = cleanName; device[@"channel"] = @(midiChannel); [self persistSimulatorDevices]; [self rebuildSimulatorDeviceRows]; return YES;
}

- (void)addSimulatorDevice:(id)sender { (void)sender; NSMutableDictionary *device = [self simulatorDeviceWithID:NSUUID.UUID.UUIDString name:@"" channel:3 enabled:YES builtIn:NO]; if ([self editDevice:device title:@"Ajouter un device MIDI"]) { [self.simulatorDevices addObject:device]; [self persistSimulatorDevices]; [self rebuildSimulatorDeviceRows]; } }
- (void)editSimulatorDevice:(NSButton *)sender { NSMutableDictionary *device = [self simulatorDeviceForID:sender.identifier]; if (self.simulatorTasks[device[@"id"]].running) [self stopSimulatorDeviceID:device[@"id"]]; [self editDevice:device title:@"Modifier le device MIDI"]; }
- (void)deleteSimulatorDevice:(NSButton *)sender { NSMutableDictionary *device = [self simulatorDeviceForID:sender.identifier]; if (!device || [device[@"built_in"] boolValue]) return; [self stopSimulatorDeviceID:device[@"id"]]; [self.simulatorDevices removeObject:device]; [self persistSimulatorDevices]; [self rebuildSimulatorDeviceRows]; }

- (void)recordSimulatorProgram:(NSInteger)program channel:(NSInteger)channel {
    for (NSMutableDictionary *device in self.simulatorDevices) {
        if ([device[@"channel"] integerValue] == channel) [self recordSimulatorProgram:program deviceID:device[@"id"]];
    }
    if (self.simulatorDeviceRows) [self rebuildSimulatorDeviceRows];
}

- (void)recordSimulatorProgram:(NSInteger)program deviceID:(NSString *)deviceID {
    NSMutableDictionary *device = [self simulatorDeviceForID:deviceID];
    if (!device || program < 0 || program > 127) return;
    NSDate *now = NSDate.date;
    NSString *title = [self simulatorSceneTitleForProgram:program channel:[device[@"channel"] integerValue]];
    NSMutableArray *history = [device[@"event_history"] isKindOfClass:NSMutableArray.class]
        ? device[@"event_history"] : [NSMutableArray array];
    [history addObject:@{@"timestamp": now, @"channel": device[@"channel"], @"midi_program": @(program),
                         @"program": @(program + 1), @"title": title, @"matched": @([title isEqualToString:self.currentAbletonSceneTitle ?: @""]),
                         @"reason": @"simulator_event"}];
    while (history.count > 10) [history removeObjectAtIndex:0];
    device[@"event_history"] = history;
    device[@"last_program"] = @(program);
    device[@"last_event_at"] = now;
    device[@"last_title"] = title;
    if (self.simulatorDeviceRows) [self rebuildSimulatorDeviceRows];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return !self.backgroundMonitorOnly; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    (void)sender;
    if (!hasVisibleWindows) [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return YES;
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    [self stopIntegratedSimulator:nil];
    [self.timer invalidate];
    [self.serviceBrowser stop];
    [self.agentServiceBrowser stop];
    if (self.guardianTask.running) [self.guardianTask terminate];
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

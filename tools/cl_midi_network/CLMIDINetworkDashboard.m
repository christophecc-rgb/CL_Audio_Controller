#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <sys/file.h>
#import <sys/socket.h>
#import <fcntl.h>
#import <unistd.h>

static int CLBackgroundMonitorLock = -1;
static NSString *const CLExpectedDiagnosticPath = @"/private/tmp/CL_MIDI_EXPECTED_DIAGNOSTIC.log";

static void CLResetExpectedDiagnostic(void) {
    [NSData.data writeToFile:CLExpectedDiagnosticPath atomically:YES];
}

static void CLExpectedDiagnostic(NSString *event, NSString *detail) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", event ?: @"EXPECTED_EVENT", detail ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized(NSFileHandle.class) {
        if (![NSFileManager.defaultManager fileExistsAtPath:CLExpectedDiagnosticPath]) {
            [data writeToFile:CLExpectedDiagnosticPath atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CLExpectedDiagnosticPath];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static SInt32 CLEndpointUniqueID(MIDIEndpointRef endpoint) {
    SInt32 uniqueID = 0;
    MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID);
    return uniqueID;
}

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
@property NSView *consoleLibrariesPanel;
@property NSTextField *consoleLibrariesMode;
@property NSTextField *cl5LibraryName;
@property NSTextField *ql1LibraryName;
@property NSTextField *cl5LibraryState;
@property NSTextField *ql1LibraryState;
@property NSTextField *appTitleLabel;
@property NSTextField *appSubtitleLabel;
@property NSTextField *compactSummary;
@property NSTextField *footerLabel;
@property NSButton *showModeButton;
@property NSButton *devicesButton;
@property NSButton *settingsButton;
@property NSButton *refreshButton;
@property BOOL showModeEnabled;
@property BOOL backgroundMonitorOnly;
@property BOOL ownsPassiveReturnMonitor;
@property BOOL expectedSourceEnumerationLogged;
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
@property NSTimer *modeSyncTimer;
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
@property NSTextField *simulatorModeLabel;
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
@property NSView *assistantReturnPanel;
@property NSScrollView *assistantDevicesScroll;
@property NSMutableDictionary<NSString *, NSDictionary *> *assistantDeviceViews;
@property NSView *assistantCL5ReturnCard;
@property NSView *assistantQL1ReturnCard;
@property NSTextField *assistantCL5ReturnProgram;
@property NSTextField *assistantQL1ReturnProgram;
@property NSTextField *assistantCL5ReturnState;
@property NSTextField *assistantQL1ReturnState;
@property NSString *currentAbletonSceneTitle;
@property NSDictionary *expectedCL5State;
@property NSDictionary *expectedQL1State;
@property MIDIClientRef returnMonitorClient;
@property MIDIEndpointRef localReturnDestination;
@property BOOL localReturnMode;
@property BOOL operatingModeChangeInFlight;
@property BOOL operatingModeSyncInFlight;
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
@property NSString *lastCL5TitleSource;
@property NSString *lastQL1TitleSource;
@property NSInteger expectedCL5Program;
@property NSInteger expectedQL1Program;
@property NSDate *expectedCL5ProgramAt;
@property NSDate *expectedQL1ProgramAt;
@property NSDictionary *lastCL5SimulatorTX;
@property NSDictionary *lastQL1SimulatorTX;
@property UInt8 expectedRunningStatus;
@property UInt8 returnRunningStatus;
@property NSUInteger sceneTitleTraceSequence;
@property NSUInteger cl5SceneTitleLookupGeneration;
@property NSUInteger ql1SceneTitleLookupGeneration;
@property NSWindow *devicesWindow;
@property NSMutableArray<NSMutableDictionary *> *deviceProfiles;
@property NSDictionary<NSNumber *, NSString *> *expectedDeviceIDByChannel;
@property NSMutableDictionary<NSString *, NSDictionary *> *expectedDeviceStates;
@property NSDictionary<NSNumber *, NSString *> *returnDeviceIDByChannel;
@property NSMutableDictionary<NSString *, NSDictionary *> *returnedDeviceStates;
@property NSPopUpButton *deviceProfileMenu;
@property NSTextField *deviceNameField;
@property NSTextField *deviceIDField;
@property NSTextField *deviceChannelField;
@property NSTextField *deviceAliasesField;
@property NSPopUpButton *devicePaletteMenu;
@property NSButton *deviceEnabledCheck;
@property NSButton *deviceShowCheck;
@property NSButton *deviceRemoteCheck;
@property NSButton *deviceNetworkCheck;
@property NSTextField *deviceConfigStatus;
@property NSPopUpButton *deviceTestDestinationMenu;
@property NSPopUpButton *deviceTestSourceMenu;
@property NSTextField *deviceTestProgramField;
@property NSTextField *deviceTestResult;
@property MIDIClientRef deviceTestClient;
@property MIDIPortRef deviceTestOutputPort;
@property MIDIPortRef deviceTestInputPort;
@property MIDIEndpointRef deviceTestSource;
@property NSDictionary *deviceTestSent;
@property NSDictionary *deviceTestReceived;
- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel receivedAt:(NSDate *)receivedAt;
- (void)queueExpectedProgram:(UInt8)program channel:(UInt8)channel;
- (void)resolveSceneTitleForMIDIProgram:(NSInteger)midiProgram channel:(UInt8)channel;
- (void)updateConsoleReturnCards;
- (void)updateRoundTripPanelForCurrentMode;
- (void)layoutAssistantViewForRTPMode:(BOOL)rtpMode;
- (void)applyOperatingMode:(NSString *)mode message:(NSString *)message;
- (void)requestOperatingMode:(NSString *)mode;
- (void)synchronizeOperatingMode;
- (void)refreshAbletonSceneTitle;
- (void)recordSimulatorProgram:(NSInteger)program channel:(NSInteger)channel;
- (void)recordSimulatorProgram:(NSInteger)program deviceID:(NSString *)deviceID;
- (void)updateConsoleLibrariesFromStatus:(NSDictionary *)status;
- (void)recordIsolatedDeviceTestProgram:(UInt8)program channel:(UInt8)channel source:(NSString *)source;
- (void)rebuildReturnDeviceRouting;
@end

static NSString *const CLExpectedEndpointName = @"Gestionnaire IAC Bus 1";
static NSString *const CLLocalReturnEndpointName = @"CL MIDI Return Test";
static NSString *const CLRTPReturnEndpointName = @"Réseau RTP MB Chris";
static NSString *const CLConsoleReturnEndpointPreference = @"consoleReturnEndpoint";
static NSInteger const CLDeviceSchemaVersion = 1;

static NSString *CLDeviceConfigurationPath(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"CL_DEVICE_CONFIG_PATH"];
    if (override.length) return override.stringByStandardizingPath;
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/CL Audio Controller/devices.json"];
}

static BOOL CLIsRTPReturnEndpointName(NSString *name) {
    if (!name.length || [name isEqualToString:CLExpectedEndpointName] ||
        [name isEqualToString:CLLocalReturnEndpointName]) return NO;
    return [name rangeOfString:@"RTP" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"Réseau" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL CLIsProtectedDeviceTestEndpoint(NSString *name) {
    if (!name.length || [name isEqualToString:CLExpectedEndpointName] ||
        [name isEqualToString:CLLocalReturnEndpointName]) return YES;
    return CLIsRTPReturnEndpointName(name);
}

static NSString *CLPreferredConsoleReturnEndpoint(NSArray<NSString *> *sources) {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:CLConsoleReturnEndpointPreference];
    if (saved.length && [sources containsObject:saved]) return saved;
    for (NSString *name in sources) {
        if ([name caseInsensitiveCompare:CLRTPReturnEndpointName] == NSOrderedSame) return name;
    }
    for (NSString *name in sources) {
        if (CLIsRTPReturnEndpointName(name)) return name;
    }
    return nil;
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
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    UInt32 byteCount = 0;
    const MIDIPacket *countedPacket = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        byteCount += countedPacket->length;
        countedPacket = MIDIPacketNext(countedPacket);
    }
    CLExpectedDiagnostic(@"EXPECTED_CALLBACK_ENTER", [NSString stringWithFormat:
        @"packet_count=%u byte_count=%u read_context=%p source_context=%p",
        (unsigned)packetList->numPackets, (unsigned)byteCount, readProcRefCon, srcConnRefCon]);
    UInt8 runningStatus = delegate.expectedRunningStatus;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        NSMutableString *hex = [NSMutableString string];
        UInt16 loggedLength = MIN(packet->length, (UInt16)64);
        for (UInt16 byteIndex = 0; byteIndex < loggedLength; byteIndex++) {
            [hex appendFormat:@"%@%02X", byteIndex ? @" " : @"", packet->data[byteIndex]];
        }
        if (packet->length > loggedLength) [hex appendFormat:@" …(+%u)", packet->length - loggedLength];
        CLExpectedDiagnostic(@"EXPECTED_PACKET", [NSString stringWithFormat:@"bytes=%@", hex]);
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 byte = packet->data[index++];
            if (byte >= 0xF8) continue; // MIDI realtime n'annule jamais le running status.
            if (byte & 0x80) {
                runningStatus = byte < 0xF0 ? byte : 0;
                continue;
            }
            if ((runningStatus & 0xF0) == 0xC0) {
                UInt8 channel = (runningStatus & 0x0F) + 1;
                CLExpectedDiagnostic(@"EXPECTED_PROGRAM_DECODED", [NSString stringWithFormat:
                    @"channel=%u raw_program=%u", channel, byte]);
                [delegate queueExpectedProgram:byte channel:channel];
            }
        }
        packet = MIDIPacketNext(packet);
    }
    delegate.expectedRunningStatus = runningStatus;
}

static void CLPassiveReturnRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)srcConnRefCon;
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    UInt8 runningStatus = delegate.returnRunningStatus;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 byte = packet->data[index++];
            if (byte >= 0xF8) continue; // MIDI realtime n'annule jamais le running status.
            if (byte & 0x80) {
                runningStatus = byte < 0xF0 ? byte : 0;
                continue;
            }
            if ((runningStatus & 0xF0) == 0xC0) {
                UInt8 channel = (runningStatus & 0x0F) + 1;
                [delegate queueReturnedProgram:byte channel:channel receivedAt:NSDate.date];
            }
        }
        packet = MIDIPacketNext(packet);
    }
    delegate.returnRunningStatus = runningStatus;
}

static void CLIsolatedDeviceTestRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)readProcRefCon;
    MIDIEndpointRef source = (MIDIEndpointRef)(uintptr_t)srcConnRefCon;
    NSString *sourceName = EndpointName(source);
    UInt8 runningStatus = 0;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        for (UInt16 index = 0; index < packet->length; index++) {
            UInt8 byte = packet->data[index];
            if (byte >= 0xF8) continue;
            if (byte & 0x80) { runningStatus = byte < 0xF0 ? byte : 0; continue; }
            if ((runningStatus & 0xF0) == 0xC0) {
                UInt8 channel = (runningStatus & 0x0F) + 1;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate recordIsolatedDeviceTestProgram:byte channel:channel source:sourceName];
                });
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
    if (self.ownsPassiveReturnMonitor) CLResetExpectedDiagnostic();
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
    self.window.title = @"CL MIDI Network Manager";
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
    NSTextField *appTitle = self.appTitleLabel = [self label:@"CL MIDI NETWORK MANAGER" frame:NSMakeRect(20, 744, 270, 24) size:15 bold:YES];
    NSTextField *appSubtitle = self.appSubtitleLabel = [self label:@"Technique RTP · CoreMIDI" frame:NSMakeRect(286, 746, 94, 20) size:9 bold:NO];
    appSubtitle.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
    NSShadow *silverShadow = [[NSShadow alloc] init];
    silverShadow.shadowColor = [NSColor colorWithWhite:1.0 alpha:0.22];
    silverShadow.shadowOffset = NSMakeSize(0, -1);
    silverShadow.shadowBlurRadius = 1.0;
    appTitle.attributedStringValue = [[NSAttributedString alloc] initWithString:@"CL MIDI NETWORK MANAGER" attributes:@{
        NSForegroundColorAttributeName: [NSColor colorWithRed:0.196 green:0.722 blue:0.612 alpha:1.0],
        NSFontAttributeName: [NSFont boldSystemFontOfSize:15.0],
        NSShadowAttributeName: silverShadow
    }];
    [content addSubview:appTitle];
    [content addSubview:appSubtitle];
    self.showModeButton = [self accentButton:@"Diagnostic détaillé" frame:NSMakeRect(354, 741, 130, 30) action:@selector(toggleShowMode:) color:[NSColor colorWithRed:0.24 green:0.28 blue:0.35 alpha:1.0]];
    [content addSubview:self.showModeButton];
    self.devicesButton = [self accentButton:@"Devices…" frame:NSMakeRect(270, 741, 76, 30) action:@selector(openDevicesEditor:) color:[NSColor colorWithRed:0.24 green:0.52 blue:0.58 alpha:1.0]];
    [content addSubview:self.devicesButton];

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
    [targetPanel addSubview:[self label:@"MODE GÉNÉRAL" frame:NSMakeRect(16, 68, 150, 20) size:10 bold:YES]];
    [targetPanel addSubview:[self label:@"CONSOLE DISTANTE RTP" frame:NSMakeRect(194, 68, 180, 20) size:10 bold:YES]];
    self.returnModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 24, 168, 34) pullsDown:NO];
    [self.returnModeMenu addItemsWithTitles:@[@"Ableton local", @"Ableton distant"]];
    self.returnModeMenu.target = self;
    self.returnModeMenu.action = @selector(returnModeChanged:);
    NSString *savedReturnMode = [NSUserDefaults.standardUserDefaults stringForKey:@"consoleReturnMode"];
    [self.returnModeMenu selectItemAtIndex:[savedReturnMode isEqualToString:@"rtp_remote"] ? 1 : 0];
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 0;
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
    self.cl5ReturnProgram = [self label:@"CL5   PC — → —   …" frame:NSMakeRect(10, 27, 190, 18) size:11 bold:YES];
    self.ql1ReturnProgram = [self label:@"QL1   PC — → —   …" frame:NSMakeRect(10, 27, 196, 18) size:11 bold:YES];
    self.cl5ReturnState = [self label:@"Indéterminé" frame:NSMakeRect(10, 7, 190, 16) size:8 bold:NO];
    self.ql1ReturnState = [self label:@"Indéterminé" frame:NSMakeRect(10, 7, 196, 16) size:8 bold:NO];
    [self.cl5ReturnCard addSubview:self.cl5ReturnProgram]; [self.cl5ReturnCard addSubview:self.cl5ReturnState];
    [self.ql1ReturnCard addSubview:self.ql1ReturnProgram]; [self.ql1ReturnCard addSubview:self.ql1ReturnState];

    self.assistantReturnPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 66, 468, 64)];
    [content addSubview:self.assistantReturnPanel];
    NSString *monitorProfileError = nil;
    self.deviceProfiles = [self loadDeviceProfilesForEditor:&monitorProfileError];
    self.expectedDeviceStates = [NSMutableDictionary dictionary];
    self.returnedDeviceStates = [NSMutableDictionary dictionary];
    [self rebuildReturnDeviceRouting];
    [self rebuildAssistantDeviceMonitoringCards];

    self.consoleLibrariesPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 293, 468, 110)];
    self.consoleLibrariesPanel.wantsLayer = YES;
    self.consoleLibrariesPanel.layer.cornerRadius = 12;
    self.consoleLibrariesPanel.layer.borderWidth = 1;
    self.consoleLibrariesPanel.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.065 blue:0.085 alpha:1.0].CGColor;
    self.consoleLibrariesPanel.layer.borderColor = [NSColor colorWithRed:0.44 green:0.62 blue:0.82 alpha:0.72].CGColor;
    [content addSubview:self.consoleLibrariesPanel];
    NSTextField *librariesTitle = [self label:@"BIBLIOTHÈQUES CONSOLES" frame:NSMakeRect(14, 82, 250, 18) size:11 bold:YES];
    librariesTitle.textColor = [NSColor colorWithRed:0.48 green:0.76 blue:1.0 alpha:1.0];
    [self.consoleLibrariesPanel addSubview:librariesTitle];
    self.consoleLibrariesMode = [self label:@"Résolution backend · vérification…" frame:NSMakeRect(250, 82, 204, 18) size:8 bold:NO];
    self.consoleLibrariesMode.alignment = NSTextAlignmentRight;
    [self.consoleLibrariesPanel addSubview:self.consoleLibrariesMode];
    [self.consoleLibrariesPanel addSubview:[self label:@"CL5" frame:NSMakeRect(14, 52, 36, 18) size:11 bold:YES]];
    self.cl5LibraryName = [self label:@"—" frame:NSMakeRect(54, 52, 150, 18) size:10 bold:YES];
    self.cl5LibraryState = [self label:@"⚠ Backend indisponible" frame:NSMakeRect(54, 31, 250, 18) size:9 bold:NO];
    [self.consoleLibrariesPanel addSubview:self.cl5LibraryName]; [self.consoleLibrariesPanel addSubview:self.cl5LibraryState];
    NSButton *modifyCL5 = [self accentButton:@"Modifier…" frame:NSMakeRect(354, 43, 100, 28) action:@selector(selectConsoleLibrary:) color:[NSColor colorWithRed:0.48 green:0.30 blue:0.72 alpha:1.0]];
    modifyCL5.identifier = @"cl5"; [self.consoleLibrariesPanel addSubview:modifyCL5];
    [self.consoleLibrariesPanel addSubview:[self label:@"QL1" frame:NSMakeRect(14, 8, 36, 18) size:11 bold:YES]];
    self.ql1LibraryName = [self label:@"—" frame:NSMakeRect(54, 8, 150, 18) size:10 bold:YES];
    self.ql1LibraryState = [self label:@"⚠ Backend indisponible" frame:NSMakeRect(208, 8, 142, 18) size:9 bold:NO];
    [self.consoleLibrariesPanel addSubview:self.ql1LibraryName]; [self.consoleLibrariesPanel addSubview:self.ql1LibraryState];
    NSButton *modifyQL1 = [self accentButton:@"Modifier…" frame:NSMakeRect(354, 3, 100, 28) action:@selector(selectConsoleLibrary:) color:[NSColor colorWithRed:0.243 green:0.620 blue:0.675 alpha:1.0]];
    modifyQL1.identifier = @"ql1"; [self.consoleLibrariesPanel addSubview:modifyQL1];

    self.settingsButton = [self accentButton:@"Réseau MIDI" frame:NSMakeRect(16, 88, 146, 36) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.27 green:0.36 blue:0.49 alpha:1.0]]; [content addSubview:self.settingsButton];
    [content addSubview:[self accentButton:@"Devices…" frame:NSMakeRect(177, 88, 146, 36) action:@selector(openDevicesEditor:) color:[NSColor colorWithRed:0.24 green:0.52 blue:0.58 alpha:1.0]]];
    self.refreshButton = [self accentButton:@"Actualiser" frame:NSMakeRect(338, 88, 146, 36) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.30 green:0.35 blue:0.43 alpha:1.0]]; [content addSubview:self.refreshButton];
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
    self.modeSyncTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(synchronizeOperatingModeTimer:) userInfo:nil repeats:YES];
    [self synchronizeOperatingMode];
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
    NSDictionary *expectedDevices = payload[@"expected_devices"];
    if ([expectedDevices isKindOfClass:NSDictionary.class]) {
        self.expectedDeviceStates = [expectedDevices mutableCopy];
    }
    NSDictionary *returnedDevices = payload[@"returned_devices"];
    if ([returnedDevices isKindOfClass:NSDictionary.class]) {
        self.returnedDeviceStates = [returnedDevices mutableCopy];
    }
    self.expectedCL5State = cl5;
    self.expectedQL1State = ql1;
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
    // Une seule instance possède le verrou et publie l'état canonique. L'UI
    // secondaire ne doit jamais écraser le JSON du moniteur de fond.
    if (!self.ownsPassiveReturnMonitor) return;
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
        @"expected_devices": self.expectedDeviceStates ?: @{},
        @"returned_devices": self.returnedDeviceStates ?: @{},

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
            @"expected_title_source": self.expectedCL5Program >= 0
                ? (self.expectedCL5State[@"expected_title_source"] ?: @"unresolved") : @"unresolved",
            @"expected_activated_at": self.expectedCL5ProgramAt ? @([self.expectedCL5ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"returned_midi_program": self.lastCL5Program >= 0 ? @(self.lastCL5Program) : NSNull.null,
            @"returned_program": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"returned_scene_memory": self.lastCL5Program >= 0 ? @(self.lastCL5Program + 1) : NSNull.null,
            @"returned_title": self.lastCL5Title.length ? self.lastCL5Title : @"Titre non résolu",
            @"returned_program_source": self.lastCL5Program >= 0 ? @"physical_midi" : @"unavailable",
            @"returned_title_source": self.lastCL5Title.length ? (self.lastCL5TitleSource ?: @"unresolved") : @"unresolved",
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
            @"local_simulator_tx": self.lastCL5SimulatorTX ?: @{},
        },

        @"ql1": @{
            @"expected_midi_program": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program) : NSNull.null,
            @"expected_program": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program + 1) : NSNull.null,
            @"expected_scene_memory": self.expectedQL1Program >= 0 ? @(self.expectedQL1Program + 1) : NSNull.null,
            @"expected_title": (self.expectedQL1State[@"expected_midi_program"] != NSNull.null &&
                [self.expectedQL1State[@"expected_midi_program"] integerValue] == self.expectedQL1Program)
                ? (self.expectedQL1State[@"expected_title"] ?: @"Titre non résolu") : @"Titre non résolu",
            @"expected_program_source": self.expectedQL1Program >= 0 ? @"ableton_iac_output" : @"unavailable",
            @"expected_title_source": self.expectedQL1Program >= 0
                ? (self.expectedQL1State[@"expected_title_source"] ?: @"unresolved") : @"unresolved",
            @"expected_activated_at": self.expectedQL1ProgramAt ? @([self.expectedQL1ProgramAt timeIntervalSince1970]) : NSNull.null,
            @"returned_midi_program": self.lastQL1Program >= 0 ? @(self.lastQL1Program) : NSNull.null,
            @"returned_program": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"returned_scene_memory": self.lastQL1Program >= 0 ? @(self.lastQL1Program + 1) : NSNull.null,
            @"returned_title": self.lastQL1Title.length ? self.lastQL1Title : @"Titre non résolu",
            @"returned_program_source": self.lastQL1Program >= 0 ? @"physical_midi" : @"unavailable",
            @"returned_title_source": self.lastQL1Title.length ? (self.lastQL1TitleSource ?: @"unresolved") : @"unresolved",
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
            @"local_simulator_tx": self.lastQL1SimulatorTX ?: @{},
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


- (NSColor *)deviceColorFromHex:(NSString *)hex fallback:(NSColor *)fallback {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *value = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if (value.length != 6) return fallback;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    if (![scanner scanHexInt:&rgb]) return fallback;

    return [NSColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

- (void)rebuildAssistantDeviceMonitoringCards {
    if (!self.assistantReturnPanel) return;

    for (NSView *view in self.assistantReturnPanel.subviews.copy) {
        [view removeFromSuperview];
    }

    self.assistantDeviceViews = [NSMutableDictionary dictionary];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.assistantReturnPanel.bounds];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;

    NSMutableArray<NSDictionary *> *visibleDevices = [NSMutableArray array];
    for (NSDictionary *device in self.deviceProfiles ?: @[]) {
        if (![device[@"enabled"] boolValue]) continue;
        NSDictionary *visibility = [device[@"visibility"] isKindOfClass:NSDictionary.class]
            ? device[@"visibility"] : @{};
        if (visibility[@"network_manager"] && ![visibility[@"network_manager"] boolValue]) continue;
        [visibleDevices addObject:device];
    }

    NSUInteger rows = MAX((NSUInteger)1, (visibleDevices.count + 1) / 2);
    CGFloat documentHeight = MAX(58.0, rows * 60.0);
    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, documentHeight)];

    for (NSUInteger index = 0; index < visibleDevices.count; index++) {
        NSDictionary *profile = visibleDevices[index];
        NSString *deviceID = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        if (!deviceID.length) continue;

        NSUInteger row = index / 2;
        NSUInteger column = index % 2;
        CGFloat x = column == 0 ? 4.0 : 230.0;
        CGFloat y = documentHeight - ((row + 1) * 60.0) + 4.0;

        NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, y, 216, 52)];
        card.wantsLayer = YES;
        card.layer.cornerRadius = 8.0;
        card.layer.borderWidth = 1.0;
        card.layer.backgroundColor =
            [NSColor colorWithRed:0.045 green:0.055 blue:0.070 alpha:1.0].CGColor;

        NSTextField *program =
            [self label:@"PC — → —   …" frame:NSMakeRect(10, 27, 196, 18) size:11 bold:YES];
        NSTextField *state =
            [self label:@"Indéterminé" frame:NSMakeRect(10, 7, 196, 16) size:8 bold:NO];

        [card addSubview:program];
        [card addSubview:state];
        [document addSubview:card];

        self.assistantDeviceViews[deviceID] = @{
            @"card": card,
            @"programLabel": program,
            @"stateLabel": state,
            @"profile": profile
        };
    }

    if (!visibleDevices.count) {
        NSTextField *empty =
            [self label:@"Aucun device actif pour Network Manager"
                  frame:NSMakeRect(8, 20, 434, 20) size:10 bold:NO];
        empty.alignment = NSTextAlignmentCenter;
        [document addSubview:empty];
    }

    scroll.documentView = document;
    self.assistantDevicesScroll = scroll;
    [self.assistantReturnPanel addSubview:scroll];

    NSDictionary *viewA = self.assistantDeviceViews[@"console_a"];
    NSDictionary *viewB = self.assistantDeviceViews[@"console_b"];

    self.assistantCL5ReturnCard = viewA[@"card"];
    self.assistantCL5ReturnProgram = viewA[@"programLabel"];
    self.assistantCL5ReturnState = viewA[@"stateLabel"];

    self.assistantQL1ReturnCard = viewB[@"card"];
    self.assistantQL1ReturnProgram = viewB[@"programLabel"];
    self.assistantQL1ReturnState = viewB[@"stateLabel"];
}

- (void)updateConsoleReturnCards {
    if (!self.deviceProfiles) {
        NSString *profileError = nil;
        self.deviceProfiles = [self loadDeviceProfilesForEditor:&profileError];
    }
    if (!self.assistantDeviceViews) {
        [self rebuildAssistantDeviceMonitoringCards];
    }

    NSMutableArray<NSDictionary *> *consoles = [NSMutableArray array];

    for (NSDictionary *profile in self.deviceProfiles ?: @[]) {
        if (![profile[@"enabled"] boolValue]) continue;

        NSDictionary *visibility = [profile[@"visibility"] isKindOfClass:NSDictionary.class]
            ? profile[@"visibility"] : @{};
        if (visibility[@"network_manager"] && ![visibility[@"network_manager"] boolValue]) continue;

        NSString *deviceID = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        NSString *name = [profile[@"display_name"] isKindOfClass:NSString.class]
            ? profile[@"display_name"] : deviceID;

        BOOL isConsoleA = [deviceID isEqualToString:@"console_a"];
        BOOL isConsoleB = [deviceID isEqualToString:@"console_b"];
        BOOL productionSupported = isConsoleA || isConsoleB;

        NSDictionary *expected = isConsoleA
            ? (self.expectedCL5State ?: @{})
            : isConsoleB
            ? (self.expectedQL1State ?: @{})
            : @{@"validation_status": @"unavailable"};

        NSMutableArray *cards = [NSMutableArray array];
        NSMutableArray *programLabels = [NSMutableArray array];
        NSMutableArray *stateLabels = [NSMutableArray array];

        if (isConsoleA && self.cl5ReturnCard) {
            [cards addObject:self.cl5ReturnCard];
            [programLabels addObject:self.cl5ReturnProgram];
            [stateLabels addObject:self.cl5ReturnState];
        } else if (isConsoleB && self.ql1ReturnCard) {
            [cards addObject:self.ql1ReturnCard];
            [programLabels addObject:self.ql1ReturnProgram];
            [stateLabels addObject:self.ql1ReturnState];
        }

        NSDictionary *assistantView = self.assistantDeviceViews[deviceID];
        if (assistantView[@"card"]) {
            [cards addObject:assistantView[@"card"]];
            [programLabels addObject:assistantView[@"programLabel"]];
            [stateLabels addObject:assistantView[@"stateLabel"]];
        }

        [consoles addObject:@{
            @"id": deviceID,
            @"name": name.length ? name : deviceID,
            @"expected": expected,
            @"cards": cards,
            @"programLabels": programLabels,
            @"stateLabels": stateLabels,
            @"palette": [profile[@"palette"] isKindOfClass:NSDictionary.class] ? profile[@"palette"] : @{},
            @"productionSupported": @(productionSupported)
        }];
    }

    for (NSDictionary *console in consoles) {
        NSDictionary *expected = console[@"expected"];
        id expectedProgramValue = expected[@"expected_scene_memory"];
        BOOL hasExpectedProgram = expectedProgramValue && expectedProgramValue != NSNull.null;
        NSInteger expectedProgram = hasExpectedProgram ? [expectedProgramValue integerValue] : -1;
        NSString *expectedTitle = [expected[@"expected_title"] isKindOfClass:NSString.class]
            ? expected[@"expected_title"] : @"Titre non résolu";
        NSString *returnedTitle = [expected[@"returned_title"] isKindOfClass:NSString.class]
            ? expected[@"returned_title"] : @"Titre non résolu";
        id returnedSceneValue = expected[@"returned_scene_memory"];
        BOOL hasCanonicalReturn = returnedSceneValue && returnedSceneValue != NSNull.null;
        BOOL hasReturn = hasCanonicalReturn;
        NSInteger receivedScene = hasReturn ? [returnedSceneValue integerValue] : -1;
        NSString *validationStatus = [expected[@"validation_status"] isKindOfClass:NSString.class] ? expected[@"validation_status"] : @"unavailable";
        BOOL confirmed = [validationStatus isEqualToString:@"confirmed"];
        BOOL mismatch = [validationStatus isEqualToString:@"mismatch"];
        BOOL stale = [validationStatus isEqualToString:@"stale"];
        BOOL localFallback = [validationStatus isEqualToString:@"local_fallback"];
        BOOL unavailable = [validationStatus isEqualToString:@"unavailable"];
        NSNumber *expectedActivatedValue = [expected[@"expected_activated_at"] isKindOfClass:NSNumber.class]
            ? expected[@"expected_activated_at"] : nil;
        NSTimeInterval elapsedSinceExpected = expectedActivatedValue
            ? MAX(0.0, NSDate.date.timeIntervalSince1970 - expectedActivatedValue.doubleValue)
            : DBL_MAX;
        BOOL actuallyWaiting = !confirmed && !mismatch && !stale && !unavailable;
        BOOL visualRecallActive = hasExpectedProgram && !mismatch &&
            (elapsedSinceExpected < 4.0 || actuallyWaiting);
        NSNumber *ageValue = [expected[@"last_return_age_seconds"] isKindOfClass:NSNumber.class]
            ? expected[@"last_return_age_seconds"] : nil;
        NSNumber *latencyValue = [expected[@"confirmation_latency_ms"] isKindOfClass:NSNumber.class]
            ? expected[@"confirmation_latency_ms"] : nil;
        NSString *expectedSource = [expected[@"expected_title_source_detail"] isKindOfClass:NSString.class]
            ? expected[@"expected_title_source_detail"] : ([expected[@"expected_title_source"] isKindOfClass:NSString.class]
                ? expected[@"expected_title_source"] : @"unresolved");
        NSString *returnedSource = [expected[@"returned_title_source_detail"] isKindOfClass:NSString.class]
            ? expected[@"returned_title_source_detail"] : ([expected[@"returned_title_source"] isKindOfClass:NSString.class]
                ? expected[@"returned_title_source"] : @"unresolved");
        NSString *expectedProgramSource = [expected[@"expected_program_source"] isKindOfClass:NSString.class]
            ? expected[@"expected_program_source"] : @"unavailable";
        NSString *returnedProgramSource = [expected[@"returned_program_source"] isKindOfClass:NSString.class]
            ? expected[@"returned_program_source"] : @"unavailable";
        NSArray *cards = console[@"cards"], *programLabels = console[@"programLabels"], *stateLabels = console[@"stateLabels"];
        NSDictionary *palette = [console[@"palette"] isKindOfClass:NSDictionary.class]
            ? console[@"palette"] : @{};
        NSColor *identityBase =
            [self deviceColorFromHex:palette[@"base"]
                            fallback:[NSColor colorWithWhite:0.68 alpha:1.0]];
        NSColor *consoleAccent =
            [self deviceColorFromHex:palette[@"accent"]
                            fallback:identityBase];
        NSColor *consoleBackground =
            [[NSColor colorWithRed:0.045 green:0.055 blue:0.070 alpha:1.0]
                blendedColorWithFraction:0.18 ofColor:identityBase];
        NSColor *consolePulseBackground = [consoleBackground blendedColorWithFraction:0.38 ofColor:consoleAccent];
        NSColor *consoleWaitingBackground = [consoleBackground blendedColorWithFraction:0.32 ofColor:consoleAccent];
        for (NSUInteger index = 0; index < cards.count; index++) {
            if (cards[index] == NSNull.null) continue;
            NSView *card = cards[index]; NSTextField *programLabel = programLabels[index]; NSTextField *stateLabel = stateLabels[index];
            NSString *expectedDisplay = hasExpectedProgram ? [NSString stringWithFormat:@"%ld", (long)expectedProgram] : @"—";
            NSString *returnedDisplay = hasReturn ? [NSString stringWithFormat:@"%ld", (long)receivedScene] : @"—";
            NSString *validationMark = confirmed ? @"✓" : mismatch ? @"✕" : stale ? @"!" : @"…";
            programLabel.stringValue = [NSString stringWithFormat:@"%@   PC %@ → %@   %@", console[@"name"], expectedDisplay, returnedDisplay, validationMark];
            stateLabel.stringValue = confirmed
                ? @"✓ Confirmé par la console"
                : mismatch
                ? [NSString stringWithFormat:@"Mismatch · reçu %ld · attendu %ld", (long)receivedScene, (long)expectedProgram]
                : stale
                ? [NSString stringWithFormat:@"Retour ancien · %@", ageValue ? CLMidiAgeDescription(ageValue.doubleValue) : @"âge indisponible"]
                : unavailable
                ? @"Indéterminé · attendu indisponible"
                : localFallback
                ? @"Secours local · en attente du retour"
                : @"En attente du retour";
            NSNumber *titleOffset = [expected[@"title_offset"] isKindOfClass:NSNumber.class] ? expected[@"title_offset"] : @0;
            id expectedLookup = expected[@"expected_title_lookup_memory"] ?: NSNull.null;
            id returnedLookup = expected[@"returned_title_lookup_memory"] ?: NSNull.null;
            (void)expectedTitle; (void)returnedTitle; (void)titleOffset; (void)expectedLookup; (void)returnedLookup;
            (void)expectedSource; (void)returnedSource; (void)expectedProgramSource; (void)returnedProgramSource; (void)latencyValue;
            card.layer.backgroundColor = consoleBackground.CGColor;
            card.layer.borderColor = consoleAccent.CGColor;
            card.layer.borderWidth = mismatch ? 3.0 : (confirmed ? 2.0 : 1.5);
            card.layer.shadowColor = consoleAccent.CGColor;
            card.layer.shadowOffset = CGSizeZero;
            card.layer.shadowOpacity = mismatch ? 0.52 : (confirmed ? 0.30 : (stale ? 0.05 : 0.16));
            card.layer.shadowRadius = mismatch ? 12.0 : (confirmed ? 8.0 : (stale ? 2.0 : 5.0));

            NSString *visualState = confirmed
                ? (visualRecallActive ? @"recall_waiting" : @"confirmed")
                : mismatch
                ? @"mismatch"
                : visualRecallActive
                ? @"recall_waiting"
                : stale
                ? @"stale"
                : unavailable
                ? @"unavailable"
                : @"waiting";

            NSString *previousVisualState = [card.layer valueForKey:@"clVisualState"];
            BOOL visualStateChanged = ![previousVisualState isEqualToString:visualState];

            if (visualRecallActive && expectedActivatedValue) {
                NSString *recallKey = [NSString stringWithFormat:@"%@|%ld|%.6f",
                    console[@"id"] ?: @"device",
                    (long)expectedProgram, expectedActivatedValue.doubleValue];
                NSString *scheduledRecallKey = [card.layer valueForKey:@"clVisualRecallTimerKey"];
                if (![scheduledRecallKey isEqualToString:recallKey]) {
                    [card.layer setValue:recallKey forKey:@"clVisualRecallTimerKey"];
                    NSTimeInterval remaining = MAX(0.0, 4.0 - elapsedSinceExpected);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((remaining + 0.01) * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        if ([[card.layer valueForKey:@"clVisualRecallTimerKey"] isEqualToString:recallKey]) {
                            [self updateConsoleReturnCards];
                        }
                    });
                }
            }

            if (visualStateChanged) {
                [card.layer removeAnimationForKey:@"clConsolePulse"];
                [card.layer setValue:visualState forKey:@"clVisualState"];
            }

            if (mismatch && [card.layer animationForKey:@"clConsolePulse"] == nil) {
                CABasicAnimation *haloPulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                haloPulse.fromValue = @0.18;
                haloPulse.toValue = @0.78;
                CABasicAnimation *backgroundPulse = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
                backgroundPulse.fromValue = (__bridge id)consoleBackground.CGColor;
                backgroundPulse.toValue = (__bridge id)consolePulseBackground.CGColor;
                CAAnimationGroup *pulse = [CAAnimationGroup animation];
                pulse.animations = @[haloPulse, backgroundPulse];
                pulse.duration = 0.55;
                pulse.autoreverses = YES;
                pulse.repeatCount = HUGE_VALF;
                pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                [card.layer addAnimation:pulse forKey:@"clConsolePulse"];
            } else if ([visualState isEqualToString:@"recall_waiting"] &&
                       [card.layer animationForKey:@"clConsolePulse"] == nil) {
                CABasicAnimation *haloPulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                haloPulse.fromValue = @0.08;
                haloPulse.toValue = @0.34;
                CABasicAnimation *backgroundPulse = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
                backgroundPulse.fromValue = (__bridge id)consoleBackground.CGColor;
                backgroundPulse.toValue = (__bridge id)consoleWaitingBackground.CGColor;
                CAAnimationGroup *pulse = [CAAnimationGroup animation];
                pulse.animations = @[haloPulse, backgroundPulse];
                pulse.duration = 1.25;
                pulse.autoreverses = YES;
                pulse.repeatCount = HUGE_VALF;
                pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                [card.layer addAnimation:pulse forKey:@"clConsolePulse"];
            } else if (confirmed && visualStateChanged) {
                CAKeyframeAnimation *haloPulse = [CAKeyframeAnimation animationWithKeyPath:@"shadowOpacity"];
                haloPulse.values = @[@0.12, @0.72, @0.30];
                haloPulse.keyTimes = @[@0.0, @0.38, @1.0];
                CAKeyframeAnimation *backgroundPulse = [CAKeyframeAnimation animationWithKeyPath:@"backgroundColor"];
                backgroundPulse.values = @[
                    (__bridge id)consoleBackground.CGColor,
                    (__bridge id)consolePulseBackground.CGColor,
                    (__bridge id)consoleBackground.CGColor
                ];
                backgroundPulse.keyTimes = @[@0.0, @0.38, @1.0];
                CAAnimationGroup *pulse = [CAAnimationGroup animation];
                pulse.animations = @[haloPulse, backgroundPulse];
                pulse.duration = 0.70;
                pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [card.layer addAnimation:pulse forKey:@"clConsolePulse"];
            }

            programLabel.textColor = consoleAccent;
            stateLabel.textColor = confirmed
                ? consoleAccent
                : mismatch
                ? [consoleAccent colorWithAlphaComponent:1.0]
                : stale
                ? [consoleAccent colorWithAlphaComponent:0.62]
                : [consoleAccent colorWithAlphaComponent:0.72];
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
            [self updateConsoleLibrariesFromStatus:payload];
            [self updateConsoleReturnCards];
        });
    }] resume];
}

- (void)updateConsoleLibrariesFromStatus:(NSDictionary *)status {
    NSDictionary *libraries = [status[@"console_scene_library_status"] isKindOfClass:NSDictionary.class]
        ? status[@"console_scene_library_status"] : @{};
    NSString *mode = [status[@"console_title_mode"] isKindOfClass:NSString.class] ? status[@"console_title_mode"] : @"";
    self.consoleLibrariesMode.stringValue = [mode isEqualToString:@"imported_library"]
        ? @"Résolution backend · bibliothèques actives"
        : @"⚠ Mode hérité : titres Ableton";
    self.consoleLibrariesMode.textColor = [mode isEqualToString:@"imported_library"]
        ? [NSColor colorWithRed:0.42 green:0.82 blue:0.58 alpha:1.0] : NSColor.systemOrangeColor;
    for (NSString *console in @[@"cl5", @"ql1"]) {
        NSDictionary *info = [libraries[console] isKindOfClass:NSDictionary.class] ? libraries[console] : @{};
        NSString *statusText = [info[@"status"] isKindOfClass:NSString.class] ? info[@"status"] : @"Backend indisponible";
        NSString *sourceName = [info[@"source_name"] isKindOfClass:NSString.class] ? info[@"source_name"] : @"";
        if (!sourceName.length && [info[@"path"] isKindOfClass:NSString.class]) sourceName = [info[@"path"] lastPathComponent];
        NSArray *entries = [info[@"entries"] isKindOfClass:NSArray.class] ? info[@"entries"] : @[];
        BOOL valid = [statusText isEqualToString:@"Valide"] && entries.count > 0;
        NSTextField *nameLabel = [console isEqualToString:@"cl5"] ? self.cl5LibraryName : self.ql1LibraryName;
        NSTextField *stateLabel = [console isEqualToString:@"cl5"] ? self.cl5LibraryState : self.ql1LibraryState;
        nameLabel.stringValue = sourceName.length ? sourceName : @"Aucune bibliothèque";
        stateLabel.stringValue = valid
            ? [NSString stringWithFormat:@"✓ %lu mémoires", (unsigned long)entries.count]
            : [NSString stringWithFormat:@"⚠ %@", statusText];
        stateLabel.textColor = valid ? [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0] : NSColor.systemOrangeColor;
    }
}

- (void)selectConsoleLibrary:(NSButton *)sender {
    NSString *console = sender.identifier.lowercaseString;
    if (![console isEqualToString:@"cl5"] && ![console isEqualToString:@"ql1"]) return;
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.allowedFileTypes = @[@"clf", @"csv", @"tsv", @"json", @"txt"];
    panel.allowsMultipleSelection = NO;
    panel.message = [NSString stringWithFormat:@"Choisir la bibliothèque %@ à importer dans le backend", console.uppercaseString];
    if ([panel runModal] != NSModalResponseOK) return;
    NSData *fileData = [NSData dataWithContentsOfURL:panel.URL];
    if (!fileData.length) { self.lastTest.stringValue = @"Bibliothèque absente ou illisible"; return; }
    NSAlert *confirmation = [[NSAlert alloc] init];
    confirmation.messageText = [NSString stringWithFormat:@"Importer %@ pour %@ ?", panel.URL.lastPathComponent, console.uppercaseString];
    confirmation.informativeText = @"Le backend validera le fichier puis remplacera sa bibliothèque canonique persistante.";
    [confirmation addButtonWithTitle:@"Importer"];
    [confirmation addButtonWithTitle:@"Annuler"];
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;
    NSString *boundary = [@"CLBoundary-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSMutableData *body = [NSMutableData data];
    NSString *header = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, panel.URL.lastPathComponent];
    [body appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:5050/console-library/import/%@", console]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = body;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Validation de la bibliothèque %@…", console.uppercaseString];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *reply = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = !error && [reply[@"ok"] boolValue];
            self.lastTest.stringValue = ok ? (reply[@"message"] ?: @"Bibliothèque importée")
                : (reply[@"message"] ?: @"Import impossible · backend indisponible");
            self.lastTest.textColor = ok ? [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0] : NSColor.systemRedColor;
            [self refreshAbletonSceneTitle];
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
        NSString *resolvedSource = [payload[@"title_source"] isKindOfClass:NSString.class]
            ? payload[@"title_source"] : @"unresolved";
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
            if (channel == 1) { self.lastCL5Title = resolvedName; self.lastCL5TitleSource = resolvedSource; }
            else { self.lastQL1Title = resolvedName; self.lastQL1TitleSource = resolvedSource; }
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            [defaults setObject:resolvedName forKey:channel == 1 ? @"lastCL5Title" : @"lastQL1Title"];
            [self writeConsoleReturnState];
        });
    }] resume];
}

- (void)setupPassiveReturnMonitor {
    if (!self.ownsPassiveReturnMonitor) return;
    OSStatus clientStatus = MIDIClientCreate(CFSTR("CL Passive Console Return Monitor"), NULL, NULL, &_returnMonitorClient);
    OSStatus expectedPortStatus = clientStatus == noErr
        ? MIDIInputPortCreate(self.returnMonitorClient, CFSTR("Ableton expected input"), CLPassiveExpectedRead,
                              (__bridge void *)self, &_expectedMonitorInputPort)
        : clientStatus;
    CLExpectedDiagnostic(@"EXPECTED_INPUT_PORT_CREATED", [NSString stringWithFormat:
        @"status=%d port=%u read_context=%p callback=CLPassiveExpectedRead",
        (int)expectedPortStatus, (unsigned)self.expectedMonitorInputPort, (__bridge void *)self]);
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
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 0;
    self.returnMonitorStatus = localStatus;
    if (!self.localReturnMode) {
        [self selectPassiveReturnSourceNamed:CLPreferredConsoleReturnEndpoint(EndpointNames(YES))];
    }
    [self updateRoundTripPanelForCurrentMode];
}

- (void)rebuildReturnDeviceRouting {
    NSMutableDictionary<NSNumber *, NSString *> *expectedRouting = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *routing = [NSMutableDictionary dictionary];
    for (NSDictionary *device in self.deviceProfiles ?: @[]) {
        if (![device[@"enabled"] boolValue]) continue;
        if (![[device[@"protocol"] lowercaseString] isEqualToString:@"midi"]) continue;
        if (![[device[@"signal_type"] lowercaseString] isEqualToString:@"program_change"]) continue;
        NSNumber *channel = [device[@"midi_channel"] isKindOfClass:NSNumber.class]
            ? device[@"midi_channel"] : nil;
        NSString *deviceID = [device[@"id"] isKindOfClass:NSString.class] ? device[@"id"] : @"";
        if (!channel || channel.integerValue < 1 || channel.integerValue > 16 || !deviceID.length) continue;
        NSDictionary *tx = [device[@"tx"] isKindOfClass:NSDictionary.class] ? device[@"tx"] : @{};
        if (!tx[@"enabled"] || [tx[@"enabled"] boolValue]) {
            if (!expectedRouting[channel]) expectedRouting[channel] = deviceID;
        }
        NSDictionary *rx = [device[@"rx"] isKindOfClass:NSDictionary.class] ? device[@"rx"] : @{};
        if ((!rx[@"enabled"] || [rx[@"enabled"] boolValue]) && !routing[channel]) {
            routing[channel] = deviceID;
        }
    }
    self.expectedDeviceIDByChannel = expectedRouting.copy;
    self.returnDeviceIDByChannel = routing.copy;
}

- (void)selectPassiveExpectedSourceNamed:(NSString *)name {
    MIDIEndpointRef selectedSource = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) {
        MIDIEndpointRef source = MIDIGetSource(index);
        NSString *sourceName = EndpointName(source);
        if (!self.expectedSourceEnumerationLogged) {
            CLExpectedDiagnostic(@"EXPECTED_SOURCE_ENUM", [NSString stringWithFormat:
                @"index=%lu endpoint=%u unique_id=%d name=%@", (unsigned long)index,
                (unsigned)source, (int)CLEndpointUniqueID(source), sourceName]);
        }
        if ([sourceName isEqualToString:name]) {
            selectedSource = source;
            CLExpectedDiagnostic(@"EXPECTED_SOURCE_SELECTED", [NSString stringWithFormat:
                @"index=%lu endpoint=%u unique_id=%d name=%@ comparison=exact", (unsigned long)index,
                (unsigned)source, (int)CLEndpointUniqueID(source), sourceName]);
            break;
        }
    }
    self.expectedSourceEnumerationLogged = YES;
    if (selectedSource == self.expectedMonitorSource) return;
    if (self.expectedMonitorSource && self.expectedMonitorInputPort) {
        MIDIPortDisconnectSource(self.expectedMonitorInputPort, self.expectedMonitorSource);
    }
    self.expectedMonitorSource = 0;
    if (selectedSource && self.expectedMonitorInputPort) {
        self.expectedMonitorStatus = MIDIPortConnectSource(
            self.expectedMonitorInputPort, selectedSource, NULL);
        CLExpectedDiagnostic(@"EXPECTED_SOURCE_CONNECTED", [NSString stringWithFormat:
            @"status=%d source=%u unique_id=%d name=%@ port=%u source_context=%p",
            (int)self.expectedMonitorStatus, (unsigned)selectedSource,
            (int)CLEndpointUniqueID(selectedSource), EndpointName(selectedSource),
            (unsigned)self.expectedMonitorInputPort, NULL]);
    }
    if (selectedSource && self.expectedMonitorInputPort && self.expectedMonitorStatus == noErr) {
        self.expectedMonitorSource = selectedSource;
    } else if (!selectedSource) self.expectedMonitorStatus = kMIDIUnknownEndpoint;
}

- (void)selectPassiveReturnSourceNamed:(NSString *)name {
    if (!self.ownsPassiveReturnMonitor) return;
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
    // Deux références nulles signifient « introuvable », pas « déjà connecté ».
    if (selectedSource && selectedSource == self.returnMonitorSource) {
        self.returnMonitorStatus = noErr;
        [self writeConsoleReturnState];
        return;
    }
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

- (void)queueReturnedProgram:(UInt8)program channel:(UInt8)channel receivedAt:(NSDate *)receivedAt {
    if (channel < 1 || channel > 16) return;
    NSString *deviceID = self.returnDeviceIDByChannel[@(channel)];
    if (!deviceID.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self recordSimulatorProgram:program channel:channel]; });
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDate *eventAt = receivedAt ?: NSDate.date;
        self.returnedDeviceStates[deviceID] = @{
            @"midi_program": @(program),
            @"returned_midi_program": @(program),
            @"scene_memory": @(program + 1),
            @"returned_scene_memory": @(program + 1),
            @"received_at": @([eventAt timeIntervalSince1970]),
            @"returned_received_at": @([eventAt timeIntervalSince1970]),
            @"source": @"physical_midi",
            @"returned_program_source": @"physical_midi",
        };
        if (channel != 1 && channel != 2) {
            [self writeConsoleReturnState];
            return;
        }
        [self traceSceneTitleEvent:@"midi-callback" midiProgram:program channel:channel
                      lookupIndex:program receivedName:nil resolvedName:nil];
        if (channel == 1) {
            self.lastCL5Program = program;
            self.lastCL5ProgramAt = eventAt;
            self.lastCL5Title = @"";
        } else {
            self.lastQL1Program = program;
            self.lastQL1ProgramAt = eventAt;
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
    if (channel < 1 || channel > 16) return;
    NSString *deviceID = self.expectedDeviceIDByChannel[@(channel)];
    if (!deviceID.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDate *receivedAt = [NSDate date];
        self.expectedDeviceStates[deviceID] = @{
            @"midi_program": @(program),
            @"expected_midi_program": @(program),
            @"scene_memory": @(program + 1),
            @"expected_scene_memory": @(program + 1),
            @"received_at": @([receivedAt timeIntervalSince1970]),
            @"expected_received_at": @([receivedAt timeIntervalSince1970]),
            @"expected_activated_at": @([receivedAt timeIntervalSince1970]),
            @"source": @"ableton_iac_output",
            @"expected_program_source": @"ableton_iac_output",
        };
        if (channel != 1 && channel != 2) {
            CLExpectedDiagnostic(@"EXPECTED_STATE_UPDATED", [NSString stringWithFormat:
                @"device_id=%@ expected_midi_program=%u", deviceID, program]);
            [self writeConsoleReturnState];
            return;
        }
        if (channel == 1) {
            self.expectedCL5Program = program;
            self.expectedCL5ProgramAt = receivedAt;
        } else {
            self.expectedQL1Program = program;
            self.expectedQL1ProgramAt = receivedAt;
        }
        CLExpectedDiagnostic(@"EXPECTED_STATE_UPDATED", [NSString stringWithFormat:
            @"console=%@ expected_midi_program=%u", channel == 1 ? @"CL5" : @"QL1", program]);
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
        [self.window setContentSize:NSMakeSize(500, 1220)];
        self.headerPanel.frame = NSMakeRect(16, 1116, 468, 88);
        self.appTitleLabel.frame = NSMakeRect(20, 1064, 270, 24);
        self.appSubtitleLabel.frame = NSMakeRect(286, 1066, 94, 20);
        self.showModeButton.frame = NSMakeRect(354, 1061, 130, 30);
        self.devicesButton.frame = NSMakeRect(270, 1061, 76, 30);
        self.statusPanel.frame = NSMakeRect(16, 971, 468, 84);
        self.targetPanel.frame = NSMakeRect(16, 863, 468, 100); self.testPanel.frame = NSMakeRect(16, 759, 468, 96);
        self.technicalPanel.frame = NSMakeRect(16, 501, 468, 250);
        self.consoleLibrariesPanel.frame = NSMakeRect(16, 381, 468, 110);
        self.simulatorPanel.frame = NSMakeRect(16, 153, 468, 220);
        self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
    } else {
        [self layoutAssistantViewForRTPMode:!self.localReturnMode];
    }
}

- (void)layoutAssistantViewForRTPMode:(BOOL)rtpMode {
    CGFloat offset = rtpMode ? 0.0 : -100.0;
    [self.window setContentSize:NSMakeSize(500, rtpMode ? 970 : 870)];
    self.headerPanel.frame = NSMakeRect(16, 866 + offset, 468, 88);
    self.appTitleLabel.frame = NSMakeRect(20, 814 + offset, 270, 24); self.appSubtitleLabel.frame = NSMakeRect(286, 816 + offset, 68, 20);
    self.showModeButton.frame = NSMakeRect(354, 811 + offset, 130, 30); self.statusPanel.frame = NSMakeRect(16, 721 + offset, 468, 84);
    self.devicesButton.frame = NSMakeRect(270, 811 + offset, 76, 30);
    self.targetPanel.frame = NSMakeRect(16, 613 + offset, 468, 100); self.testPanel.frame = NSMakeRect(16, 509, 468, 96);
    self.assistantReturnPanel.frame = NSMakeRect(16, 437, 468, 64);
    self.consoleLibrariesPanel.frame = NSMakeRect(16, 317, 468, 110);
    self.simulatorPanel.frame = NSMakeRect(16, 63, 468, 220);
    self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
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
    if (!self.showModeEnabled) [self layoutAssistantViewForRTPMode:rtpMode];
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
        NSString *preferred = CLPreferredConsoleReturnEndpoint(EndpointNames(YES));
        if (preferred.length) [self.endpointMenu selectItemWithTitle:preferred];
        self.lastTest.stringValue = @"Endpoint interne refusé comme console distante";
        return;
    }

    if (endpoint.length && ![endpoint hasPrefix:@"Aucun"]) {
        [NSUserDefaults.standardUserDefaults setObject:endpoint forKey:CLConsoleReturnEndpointPreference];
        if (!self.localReturnMode) [self selectPassiveReturnSourceNamed:endpoint];
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
    [self requestOperatingMode:self.returnModeMenu.indexOfSelectedItem == 0 ? @"local" : @"remote"];
}

- (void)applyOperatingMode:(NSString *)mode message:(NSString *)message {
    BOOL local = [mode isEqualToString:@"local"];
    if (!local && ![mode isEqualToString:@"remote"]) return;
    BOOL changed = self.localReturnMode != local;
    self.localReturnMode = local;
    [self.returnModeMenu selectItemAtIndex:local ? 0 : 1];
    if (self.simulatorModeLabel) self.simulatorModeLabel.stringValue = local ? @"Ableton local · dérivé du mode général" : @"Ableton distant · dérivé du mode général";
    [NSUserDefaults.standardUserDefaults setObject:(local ? @"local_dedicated" : @"rtp_remote")
                                            forKey:@"consoleReturnMode"];
    if (!changed) {
        if (message.length) self.lastTest.stringValue = message;
        [self updateRoundTripPanelForCurrentMode];
        return;
    }
    [self simulatorModeChanged:nil];
    if (message.length) self.lastTest.stringValue = message;
}

- (void)synchronizeOperatingMode {
    if (self.operatingModeChangeInFlight || self.operatingModeSyncInFlight) return;
    self.operatingModeSyncInFlight = YES;
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5055/network-config"];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSDictionary *payload = (!error && http.statusCode == 200 && data.length)
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *mode = [payload[@"active_mode"] isKindOfClass:NSString.class] ? payload[@"active_mode"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.operatingModeSyncInFlight = NO;
            if (mode.length && !self.operatingModeChangeInFlight) [self applyOperatingMode:mode message:nil];
        });
    }] resume];
}

- (void)synchronizeOperatingModeTimer:(NSTimer *)timer {
    (void)timer;
    [self synchronizeOperatingMode];
}

- (void)requestOperatingMode:(NSString *)mode {
    if (self.operatingModeChangeInFlight) return;
    self.operatingModeChangeInFlight = YES;
    self.returnModeMenu.enabled = NO;
    self.lastTest.stringValue = @"Application du mode général…";
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5055/network-config"];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSDictionary *configuration = (!error && http.statusCode == 200 && data.length)
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *profiles = [configuration[@"profiles"] isKindOfClass:NSDictionary.class] ? configuration[@"profiles"] : nil;
        NSDictionary *profile = [profiles[mode] isKindOfClass:NSDictionary.class] ? profiles[mode] : nil;
        if (!profile) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.operatingModeChangeInFlight = NO;
                self.returnModeMenu.enabled = YES;
                [self synchronizeOperatingMode];
                self.lastTest.stringValue = error ? @"CL Audio Show Control est indisponible" : @"Profil Ableton distant non configuré";
            });
            return;
        }
        NSMutableDictionary *payload = [@{
            @"mode": mode, @"host": profile[@"host"] ?: @"",
            @"send_port": profile[@"send_port"] ?: @11000,
            @"reply_port": profile[@"reply_port"] ?: @11001
        } mutableCopy];
        if ([profile[@"name"] isKindOfClass:NSString.class]) payload[@"name"] = profile[@"name"];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *replyData, NSURLResponse *replyResponse, NSError *replyError) {
            NSHTTPURLResponse *replyHTTP = (NSHTTPURLResponse *)replyResponse;
            NSDictionary *reply = replyData.length ? [NSJSONSerialization JSONObjectWithData:replyData options:0 error:nil] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.operatingModeChangeInFlight = NO;
                self.returnModeMenu.enabled = YES;
                if (!replyError && replyHTTP.statusCode == 200) {
                    NSString *message = [mode isEqualToString:@"local"] ? @"Ableton local · retour dédié actif" : @"Ableton distant · diagnostic RTP actif";
                    [self applyOperatingMode:mode message:message];
                } else {
                    [self synchronizeOperatingMode];
                    NSString *reason = [reply[@"error"] isKindOfClass:NSString.class] ? reply[@"error"] : @"changement refusé";
                    self.lastTest.stringValue = [NSString stringWithFormat:@"Mode inchangé · %@", reason];
                }
            });
        }] resume];
    }] resume];
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
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:CLConsoleReturnEndpointPreference];
    NSString *preferred = ([candidates containsObject:selected] ? selected : nil) ?:
        ([candidates containsObject:saved] ? saved : CLPreferredConsoleReturnEndpoint(sources));
    if (preferred.length && [candidates containsObject:preferred]) {
        [self.endpointMenu selectItemWithTitle:preferred];
        [NSUserDefaults.standardUserDefaults setObject:preferred forKey:CLConsoleReturnEndpointPreference];
    }
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];

    if (self.simulatorEndpointMenu && !self.localReturnMode) {
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
    if (!self.localReturnMode) [self selectPassiveReturnSourceNamed:preferred];
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
        self.localReturnMode ? CLLocalReturnEndpointName : (preferred ?: @"aucune"),
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
    NSView *content = self.simulatorPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 153, 468, 220)];
    content.wantsLayer = YES; content.layer.cornerRadius = 12; content.layer.borderWidth = 1;
    content.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.060 blue:0.045 alpha:1.0].CGColor;
    content.layer.borderColor = [NSColor colorWithRed:0.72 green:0.43 blue:0.18 alpha:0.72].CGColor;
    [parent addSubview:content];

    NSTextField *title = [self label:@"SIMULATEUR DE RETOUR CONSOLE" frame:NSMakeRect(14, 192, 360, 20) size:11 bold:YES];
    title.textColor = [NSColor colorWithRed:1.0 green:0.68 blue:0.28 alpha:1.0];
    [content addSubview:title];

    [content addSubview:[self label:@"MODE GÉNÉRAL (AUTOMATIQUE)" frame:NSMakeRect(14, 171, 170, 14) size:8 bold:YES]];
    self.simulatorModeLabel = [self label:@"" frame:NSMakeRect(14, 143, 170, 28) size:10 bold:YES];
    self.simulatorModeLabel.textColor = [NSColor colorWithRed:0.92 green:0.58 blue:0.26 alpha:1.0];
    [content addSubview:self.simulatorModeLabel];

    self.simulatorEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(190, 143, 130, 28) pullsDown:NO];
    [self.simulatorEndpointMenu addItemWithTitle:CLLocalReturnEndpointName];
    self.simulatorEndpointMenu.target = self;
    self.simulatorEndpointMenu.action = @selector(simulatorEndpointChanged:);
    [self stylePopup:self.simulatorEndpointMenu accent:[NSColor colorWithRed:0.44 green:0.76 blue:1.0 alpha:1.0]];
    [content addSubview:self.simulatorEndpointMenu];
    [content addSubview:[self label:@"DESTINATION" frame:NSMakeRect(194, 171, 120, 14) size:8 bold:YES]];

    [content addSubview:[self label:@"SOURCE AUTO" frame:NSMakeRect(334, 171, 120, 14) size:8 bold:YES]];
    self.simulatorInputEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(326, 143, 128, 28) pullsDown:NO];
    [self.simulatorInputEndpointMenu addItemWithTitle:@"Aucune"];
    self.simulatorInputEndpointMenu.target = self;
    self.simulatorInputEndpointMenu.action = @selector(simulatorInputEndpointChanged:);
    [self stylePopup:self.simulatorInputEndpointMenu accent:[NSColor colorWithRed:0.62 green:0.62 blue:0.68 alpha:1.0]];
    [content addSubview:self.simulatorInputEndpointMenu];

    NSView *cl5Row = [[NSView alloc] initWithFrame:NSMakeRect(14, 96, 440, 38)]; cl5Row.wantsLayer = YES; cl5Row.layer.cornerRadius = 8; cl5Row.layer.backgroundColor = [NSColor colorWithRed:0.105 green:0.080 blue:0.135 alpha:1.0].CGColor; cl5Row.layer.borderColor = [NSColor colorWithRed:0.608 green:0.420 blue:0.839 alpha:1.0].CGColor; cl5Row.layer.borderWidth = 1; [content addSubview:cl5Row];
    NSTextField *cl5Label = [self label:@"CL5 · Program Change · Canal 1" frame:NSMakeRect(12, 9, 190, 20) size:10 bold:YES]; cl5Label.textColor = [NSColor colorWithRed:0.72 green:0.56 blue:0.93 alpha:1.0]; [cl5Row addSubview:cl5Label];
    self.simulatorCL5MemoryField = [[NSTextField alloc] initWithFrame:NSMakeRect(206, 6, 54, 26)];
    self.simulatorCL5MemoryField.stringValue = @"81"; self.simulatorCL5MemoryField.alignment = NSTextAlignmentCenter; [cl5Row addSubview:self.simulatorCL5MemoryField];
    NSButton *sendCL5 = [self accentButton:@"Envoyer" frame:NSMakeRect(268, 5, 80, 28) action:@selector(sendSimulatorMemory:) color:[NSColor colorWithRed:0.48 green:0.30 blue:0.72 alpha:1.0]];
    sendCL5.tag = 1; [cl5Row addSubview:sendCL5];

    NSView *ql1Row = [[NSView alloc] initWithFrame:NSMakeRect(14, 54, 440, 38)]; ql1Row.wantsLayer = YES; ql1Row.layer.cornerRadius = 8; ql1Row.layer.backgroundColor = [NSColor colorWithRed:0.060 green:0.125 blue:0.145 alpha:1.0].CGColor; ql1Row.layer.borderColor = [NSColor colorWithRed:0.243 green:0.620 blue:0.675 alpha:1.0].CGColor; ql1Row.layer.borderWidth = 1; [content addSubview:ql1Row];
    NSTextField *ql1Label = [self label:@"QL1 · Program Change · Canal 2" frame:NSMakeRect(12, 9, 190, 20) size:10 bold:YES]; ql1Label.textColor = [NSColor colorWithRed:0.388 green:0.780 blue:0.831 alpha:1.0]; [ql1Row addSubview:ql1Label];
    self.simulatorQL1MemoryField = [[NSTextField alloc] initWithFrame:NSMakeRect(206, 6, 54, 26)];
    self.simulatorQL1MemoryField.stringValue = @"78"; self.simulatorQL1MemoryField.alignment = NSTextAlignmentCenter; [ql1Row addSubview:self.simulatorQL1MemoryField];
    NSButton *sendQL1 = [self accentButton:@"Envoyer" frame:NSMakeRect(268, 5, 80, 28) action:@selector(sendSimulatorMemory:) color:[NSColor colorWithRed:0.243 green:0.620 blue:0.675 alpha:1.0]];
    sendQL1.tag = 2; [ql1Row addSubview:sendQL1];

    [cl5Row addSubview:[self label:@"Délai" frame:NSMakeRect(354, 10, 34, 18) size:8 bold:NO]];
    self.simulatorDelayField = [[NSTextField alloc] initWithFrame:NSMakeRect(388, 6, 36, 26)];
    self.simulatorDelayField.stringValue = @"80";
    self.simulatorDelayField.alignment = NSTextAlignmentCenter;
    [cl5Row addSubview:self.simulatorDelayField];
    [content addSubview:[self accentButton:@"ACTIVER TEST" frame:NSMakeRect(14, 14, 126, 30) action:@selector(startIntegratedSimulator:) color:[NSColor colorWithRed:0.10 green:0.56 blue:0.31 alpha:1.0]]];
    [content addSubview:[self accentButton:@"ARRÊTER TOUT" frame:NSMakeRect(148, 14, 118, 30) action:@selector(stopIntegratedSimulator:) color:[NSColor colorWithRed:0.58 green:0.18 blue:0.20 alpha:1.0]]];
    self.simulatorStatusLabel = [self label:@"Simulation désactivée" frame:NSMakeRect(276, 16, 178, 24) size:9 bold:YES];
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
    NSString *endpoint = self.localReturnMode ? CLLocalReturnEndpointName : self.simulatorEndpointMenu.titleOfSelectedItem;
    if (self.localReturnMode && !self.localReturnDestination) {
        self.simulatorStatusLabel.stringValue = @"RETURNED absent : CL MIDI Return Test introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return;
    }
    if (!self.localReturnMode && ![CLLocalRTPEndpointNames() containsObject:endpoint]) {
        self.simulatorStatusLabel.stringValue = @"Endpoint RTP local introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return;
    }
    if (self.localReturnMode) {
        // CL MIDI Return Test est volontairement une destination virtuelle
        // uniquement. Un envoi local ne doit donc pas exiger de source
        // CoreMIDI homonyme ni passer par CLMIDIRoundTripTester.
        MIDIEndpointRef destination = self.localReturnDestination;
        MIDIPortRef outputPort = 0;
        OSStatus portStatus = MIDIOutputPortCreate(
            self.returnMonitorClient,
            CFSTR("CL Local Simulator Output"),
            &outputPort
        );
        if (portStatus != noErr || !outputPort) {
            self.simulatorStatusLabel.stringValue =
                [NSString stringWithFormat:@"Envoi impossible · MIDIOutputPortCreate status=%d", (int)portStatus];
            self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
            CLAppendDiagnostic(
                @"integrated-simulator-manual-send-error",
                [NSString stringWithFormat:@"stage=output-port status=%d channel=%ld memory=%ld endpoint=%@",
                 (int)portStatus, (long)channel, (long)sceneMemory, endpoint]
            );
            return;
        }

        UInt8 midiProgram = (UInt8)(sceneMemory - 1);
        UInt8 statusByte = (UInt8)(0xC0 | ((channel - 1) & 0x0F));

        MIDIPacketList packetList;
        packetList.numPackets = 1;
        packetList.packet[0].timeStamp = 0;
        packetList.packet[0].length = 2;
        packetList.packet[0].data[0] = statusByte;
        packetList.packet[0].data[1] = midiProgram;

        OSStatus sendStatus = MIDISend(outputPort, destination, &packetList);
        MIDIPortDispose(outputPort);

        if (sendStatus != noErr) {
            self.simulatorStatusLabel.stringValue =
                [NSString stringWithFormat:@"Envoi impossible · MIDISend status=%d", (int)sendStatus];
            self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
            CLAppendDiagnostic(
                @"integrated-simulator-manual-send-error",
                [NSString stringWithFormat:@"stage=send status=%d channel=%ld memory=%ld midi_program=%u endpoint=%@",
                 (int)sendStatus, (long)channel, (long)sceneMemory, (unsigned)midiProgram, endpoint]
            );
            return;
        }

        [self recordSimulatorProgram:midiProgram channel:channel];
        self.simulatorStatusLabel.stringValue =
            [NSString stringWithFormat:@"%@ · mémoire %ld envoyée", channel == 1 ? @"CL5" : @"QL1", (long)sceneMemory];
        self.simulatorStatusLabel.textColor =
            [NSColor colorWithRed:1.0 green:0.68 blue:0.28 alpha:1.0];

        CLAppendDiagnostic(
            @"integrated-simulator-manual-send",
            [NSString stringWithFormat:@"status=0 channel=%ld memory=%ld midi_program=%u endpoint=%@",
             (long)channel, (long)sceneMemory, (unsigned)midiProgram, endpoint]
        );
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLYamahaConsoleSimulator"]];
    task.arguments = @[@"--label", channel == 1 ? @"CL5" : @"QL1",
                       @"--channel", [NSString stringWithFormat:@"%ld", (long)channel],
                       @"--transport", @"rtp", @"--endpoint", endpoint,
                       @"--send-program", [NSString stringWithFormat:@"%ld", (long)sceneMemory], @"--no-echo"];
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
    self.simulatorModeLabel.stringValue = self.localReturnMode ? @"Ableton local · dérivé du mode général" : @"Ableton distant · dérivé du mode général";
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
        if (![CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName]) {
            self.simulatorStatusLabel.stringValue = @"EXPECTED absent : Gestionnaire IAC Bus 1 introuvable";
            self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        } else if (!self.localReturnDestination) {
            self.simulatorStatusLabel.stringValue = @"RETURNED absent : CL MIDI Return Test introuvable";
            self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        }
    }
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
        self.returnMonitorSource = 0;
    }
    if (self.localReturnMode) self.returnMonitorStatus = self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;
    else {
        NSString *preferred = CLPreferredConsoleReturnEndpoint(EndpointNames(YES));
        if (preferred.length) [self.endpointMenu selectItemWithTitle:preferred];
        [self selectPassiveReturnSourceNamed:preferred];
    }
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
    BOOL local = self.localReturnMode;
    NSString *selectedEndpoint = self.simulatorEndpointMenu.titleOfSelectedItem ?: @"";
    if ([selectedEndpoint isEqualToString:CLExpectedEndpointName]) {
        self.simulatorStatusLabel.stringValue = @"Retour simulé refusé · Gestionnaire IAC Bus 1 est exclusivement la source expected";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    NSString *requiredEndpoint = local ? CLLocalReturnEndpointName : selectedEndpoint;
    if (local && ![CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName]) {
        self.simulatorStatusLabel.stringValue = @"EXPECTED absent : Gestionnaire IAC Bus 1 introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    if (local && !self.localReturnDestination) {
        self.simulatorStatusLabel.stringValue = @"RETURNED absent : CL MIDI Return Test introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    if (!local && ![CLLocalRTPEndpointNames() containsObject:requiredEndpoint]) {
        self.simulatorStatusLabel.stringValue = @"Endpoint RTP local introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    if (!local) {
        NSString *input = self.simulatorInputEndpointMenu.titleOfSelectedItem ?: @"Aucune";
        if (![input isEqualToString:@"Aucune"] && ![CLSimulatorInputEndpointNames() containsObject:input]) {
            [self.simulatorInputEndpointMenu selectItemWithTitle:@"Aucune"];
            self.simulatorStatusLabel.stringValue = [NSString stringWithFormat:@"Source automatique indisponible : %@ · envoi manuel RTP disponible", input];
        }
        [NSUserDefaults.standardUserDefaults setObject:requiredEndpoint forKey:@"simulatorLocalRtpEndpoint"];
    }
    if (transport) *transport = local ? @"iac" : @"rtp";
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
    NSDictionary *publication = @{ @"console": [device[@"channel"] integerValue] == 1 ? @"CL5" : @"QL1",
        @"channel": device[@"channel"], @"midi_program": @(program), @"scene_memory": @(program + 1),
        @"timestamp": @([now timeIntervalSince1970]), @"source": @"local_simulator_tx",
        @"title": title ?: @"" };
    if ([device[@"channel"] integerValue] == 1) self.lastCL5SimulatorTX = publication;
    else if ([device[@"channel"] integerValue] == 2) self.lastQL1SimulatorTX = publication;
    [self writeConsoleReturnState];
    if (self.simulatorDeviceRows) [self rebuildSimulatorDeviceRows];
}

#pragma mark - Device Profiles editor (configuration only)

- (NSButton *)deviceCheck:(NSString *)title frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.buttonType = NSButtonTypeSwitch; button.title = title;
    button.font = [NSFont systemFontOfSize:10]; return button;
}

- (void)openDevicesEditor:(id)sender {
    (void)sender;
    if (self.devicesWindow) { [self.devicesWindow makeKeyAndOrderFront:nil]; return; }
    self.devicesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 690)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.devicesWindow.title = @"CL MIDI Network Manager · Devices";
    self.devicesWindow.delegate = self;
    [self.devicesWindow center];
    NSView *content = self.devicesWindow.contentView; content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithRed:0.045 green:0.052 blue:0.066 alpha:1.0].CGColor;
    [content addSubview:[self label:@"DEVICES" frame:NSMakeRect(20, 650, 200, 24) size:17 bold:YES]];
    NSTextField *intro = [self label:@"Configuration uniquement · moteur production historique inchangé" frame:NSMakeRect(200, 650, 490, 22) size:10 bold:NO]; intro.alignment = NSTextAlignmentRight; [content addSubview:intro];
    self.deviceProfileMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 604, 260, 32) pullsDown:NO]; self.deviceProfileMenu.target = self; self.deviceProfileMenu.action = @selector(deviceProfileChanged:); [content addSubview:self.deviceProfileMenu];
    [content addSubview:[self accentButton:@"+ Ajouter" frame:NSMakeRect(292, 604, 100, 32) action:@selector(addDeviceProfile:) color:[NSColor colorWithRed:0.22 green:0.48 blue:0.68 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Supprimer" frame:NSMakeRect(402, 604, 100, 32) action:@selector(deleteDeviceProfile:) color:[NSColor colorWithRed:0.56 green:0.24 blue:0.27 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Par défaut" frame:NSMakeRect(512, 604, 90, 32) action:@selector(restoreDefaultDeviceProfiles:) color:[NSColor colorWithRed:0.36 green:0.34 blue:0.46 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Enregistrer" frame:NSMakeRect(612, 604, 88, 32) action:@selector(saveDeviceProfiles:) color:[NSColor colorWithRed:0.12 green:0.52 blue:0.35 alpha:1.0]]];

    NSArray *labels = @[@"Nom affiché", @"ID interne", @"Canal MIDI", @"Alias Ableton (séparés par virgules)", @"Palette"];
    NSArray *ys = @[@552, @508, @464, @420, @376];
    for (NSUInteger i = 0; i < labels.count; i++) [content addSubview:[self label:labels[i] frame:NSMakeRect(22, [ys[i] doubleValue] + 25, 250, 16) size:9 bold:YES]];
    self.deviceNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 548, 320, 28)]; [content addSubview:self.deviceNameField];
    self.deviceIDField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 504, 320, 28)]; self.deviceIDField.editable = NO; self.deviceIDField.textColor = NSColor.secondaryLabelColor; [content addSubview:self.deviceIDField];
    self.deviceChannelField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 100, 28)]; [content addSubview:self.deviceChannelField];
    [content addSubview:[self label:@"Type : Console    Protocole : MIDI    Signal : Program Change" frame:NSMakeRect(140, 462, 420, 22) size:10 bold:YES]];
    self.deviceAliasesField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 416, 680, 28)]; [content addSubview:self.deviceAliasesField];
    self.devicePaletteMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 372, 180, 30) pullsDown:NO]; [self.devicePaletteMenu addItemsWithTitles:@[@"Violet", @"Cyan", @"Bleu", @"Orange", @"Rose", @"Jaune", @"Rouge", @"Vert", @"Personnalisée"]]; self.devicePaletteMenu.target = self; self.devicePaletteMenu.action = @selector(devicePaletteChanged:); [content addSubview:self.devicePaletteMenu];
    self.deviceEnabledCheck = [self deviceCheck:@"Actif" frame:NSMakeRect(220, 373, 90, 26)]; [content addSubview:self.deviceEnabledCheck];
    self.deviceShowCheck = [self deviceCheck:@"Show" frame:NSMakeRect(330, 373, 90, 26)]; [content addSubview:self.deviceShowCheck];
    self.deviceRemoteCheck = [self deviceCheck:@"Remote" frame:NSMakeRect(430, 373, 100, 26)]; [content addSubview:self.deviceRemoteCheck];
    self.deviceNetworkCheck = [self deviceCheck:@"Network" frame:NSMakeRect(540, 373, 110, 26)]; [content addSubview:self.deviceNetworkCheck];
    self.deviceConfigStatus = [self label:@"" frame:NSMakeRect(20, 337, 680, 24) size:10 bold:YES]; [content addSubview:self.deviceConfigStatus];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(20, 320, 680, 1)]; separator.boxType = NSBoxSeparator; [content addSubview:separator];
    [content addSubview:[self label:@"DEVICE TEST · ÉTAT ISOLÉ" frame:NSMakeRect(20, 286, 280, 22) size:14 bold:YES]];
    NSTextField *warning = [self label:@"Endpoints EXPECTED, RETURNED et RTP masqués pour éviter toute pollution du show" frame:NSMakeRect(280, 286, 420, 20) size:9 bold:NO]; warning.alignment = NSTextAlignmentRight; warning.textColor = [NSColor colorWithRed:1.0 green:0.68 blue:0.30 alpha:1.0]; [content addSubview:warning];
    [content addSubview:[self label:@"Destination TX sûre" frame:NSMakeRect(20, 254, 180, 16) size:9 bold:YES]];
    [content addSubview:[self label:@"Source RX sûre" frame:NSMakeRect(260, 254, 180, 16) size:9 bold:YES]];
    [content addSubview:[self label:@"Mémoire 1–128" frame:NSMakeRect(500, 254, 150, 16) size:9 bold:YES]];
    self.deviceTestDestinationMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 218, 220, 30) pullsDown:NO]; [content addSubview:self.deviceTestDestinationMenu];
    self.deviceTestSourceMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(260, 218, 220, 30) pullsDown:NO]; [content addSubview:self.deviceTestSourceMenu];
    self.deviceTestProgramField = [[NSTextField alloc] initWithFrame:NSMakeRect(500, 218, 90, 30)]; self.deviceTestProgramField.alignment = NSTextAlignmentCenter; [content addSubview:self.deviceTestProgramField];
    [content addSubview:[self accentButton:@"TEST TX" frame:NSMakeRect(20, 166, 150, 34) action:@selector(sendIsolatedDeviceTestTX:) color:[NSColor colorWithRed:0.40 green:0.34 blue:0.70 alpha:1.0]]];
    [content addSubview:[self accentButton:@"LISTEN RX" frame:NSMakeRect(190, 166, 150, 34) action:@selector(startIsolatedDeviceTestRX:) color:[NSColor colorWithRed:0.22 green:0.48 blue:0.68 alpha:1.0]]];
    [content addSubview:[self accentButton:@"ROUND TRIP TEST" frame:NSMakeRect(360, 166, 180, 34) action:@selector(runIsolatedDeviceRoundTrip:) color:[NSColor colorWithRed:0.16 green:0.56 blue:0.36 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Actualiser endpoints" frame:NSMakeRect(560, 166, 140, 34) action:@selector(refreshIsolatedDeviceTestEndpoints:) color:[NSColor colorWithWhite:0.28 alpha:1.0]]];
    self.deviceTestResult = [self label:@"Aucun TEST TX/RX exécuté" frame:NSMakeRect(20, 82, 680, 68) size:11 bold:YES]; self.deviceTestResult.maximumNumberOfLines = 3; [content addSubview:self.deviceTestResult];
    NSTextField *footer = [self label:@"Le Test Bench n’appelle jamais queueExpectedProgram, queueReturnedProgram ni writeConsoleReturnState." frame:NSMakeRect(20, 34, 680, 28) size:9 bold:NO]; footer.textColor = NSColor.secondaryLabelColor; [content addSubview:footer];

    NSString *loadError = nil; self.deviceProfiles = [self loadDeviceProfilesForEditor:&loadError];
    [self refreshDeviceProfileMenuSelectingID:@"console_a"]; [self refreshIsolatedDeviceTestEndpoints:nil];
    if (loadError.length) { self.deviceConfigStatus.stringValue = loadError; self.deviceConfigStatus.textColor = NSColor.systemRedColor; }
    [self.devicesWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}

- (NSDictionary *)defaultDeviceConfigurationPayload {
    return @{ @"schema_version": @(CLDeviceSchemaVersion), @"profile_id": @"default",
        @"profile_name": @"Configuration par défaut", @"devices": @[
        @{ @"id": @"console_a", @"display_name": @"CL5", @"enabled": @YES,
           @"device_type": @"console", @"protocol": @"midi", @"signal_type": @"program_change",
           @"midi_channel": @1, @"ableton_track_aliases": @[@"PGM CHANGE CL5"],
           @"palette": @{ @"base": @"#C09AF2", @"accent": @"#9B6BD6" }, @"library": @"cl5",
           @"legacy_key": @"cl5", @"visibility": @{ @"show_control": @YES, @"remote": @YES, @"network_manager": @YES },
           @"tx": @{ @"enabled": @YES }, @"rx": @{ @"enabled": @YES } },
        @{ @"id": @"console_b", @"display_name": @"QL1", @"enabled": @YES,
           @"device_type": @"console", @"protocol": @"midi", @"signal_type": @"program_change",
           @"midi_channel": @2, @"ableton_track_aliases": @[@"PGM CHANGE QL1"],
           @"palette": @{ @"base": @"#63C7D4", @"accent": @"#3E9EAC" }, @"library": @"ql1",
           @"legacy_key": @"ql1", @"visibility": @{ @"show_control": @YES, @"remote": @YES, @"network_manager": @YES },
           @"tx": @{ @"enabled": @YES }, @"rx": @{ @"enabled": @YES } }
    ] };
}

- (NSDictionary *)devicePalettePresets {
    return @{ @"Violet": @[@"#C09AF2", @"#9B6BD6"], @"Cyan": @[@"#63C7D4", @"#3E9EAC"],
        @"Bleu": @[@"#79B8FF", @"#397FD1"], @"Orange": @[@"#FFB067", @"#D7782D"],
        @"Rose": @[@"#F49BC4", @"#C75B8D"], @"Jaune": @[@"#F4D96B", @"#C5A52E"],
        @"Rouge": @[@"#F08A8A", @"#C64D4D"], @"Vert": @[@"#83D6A0", @"#3E9B62"] };
}

- (NSMutableArray<NSMutableDictionary *> *)loadDeviceProfilesForEditor:(NSString **)errorMessage {
    NSData *data = [NSData dataWithContentsOfFile:CLDeviceConfigurationPath()];
    NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (data.length && (![payload isKindOfClass:NSDictionary.class] || [payload[@"schema_version"] integerValue] != CLDeviceSchemaVersion || ![payload[@"devices"] isKindOfClass:NSArray.class])) {
        if (errorMessage) *errorMessage = @"devices.json invalide · valeurs CL5 / QL1 par défaut utilisées";
        payload = [self defaultDeviceConfigurationPayload];
    }
    if (!payload) payload = [self defaultDeviceConfigurationPayload];
    NSMutableArray *devices = [NSMutableArray array];
    for (NSDictionary *item in payload[@"devices"]) {
        if ([item isKindOfClass:NSDictionary.class]) [devices addObject:[item mutableCopy]];
    }
    return devices;
}

- (NSMutableDictionary *)selectedDeviceProfile {
    NSInteger index = self.deviceProfileMenu.indexOfSelectedItem;
    return index >= 0 && index < (NSInteger)self.deviceProfiles.count ? self.deviceProfiles[index] : nil;
}

- (void)refreshDeviceProfileMenuSelectingID:(NSString *)selectedID {
    [self.deviceProfileMenu removeAllItems];
    NSInteger selectedIndex = 0;
    for (NSUInteger index = 0; index < self.deviceProfiles.count; index++) {
        NSDictionary *device = self.deviceProfiles[index];
        NSString *title = [NSString stringWithFormat:@"%@%@", [device[@"enabled"] boolValue] ? @"" : @"○ ", device[@"display_name"] ?: @"Device"];
        [self.deviceProfileMenu addItemWithTitle:title];
        if ([device[@"id"] isEqualToString:selectedID]) selectedIndex = index;
    }
    if (self.deviceProfiles.count) [self.deviceProfileMenu selectItemAtIndex:selectedIndex];
    [self populateDeviceEditorFields];
}

- (void)populateDeviceEditorFields {
    NSDictionary *device = [self selectedDeviceProfile];
    if (!device) return;
    self.deviceNameField.stringValue = device[@"display_name"] ?: @"";
    self.deviceIDField.stringValue = device[@"id"] ?: @"";
    self.deviceChannelField.stringValue = [device[@"midi_channel"] stringValue] ?: @"";
    self.deviceAliasesField.stringValue = [device[@"ableton_track_aliases"] componentsJoinedByString:@", "] ?: @"";
    self.deviceEnabledCheck.state = [device[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSDictionary *visibility = device[@"visibility"];
    self.deviceShowCheck.state = [visibility[@"show_control"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceRemoteCheck.state = [visibility[@"remote"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceNetworkCheck.state = [visibility[@"network_manager"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSArray *colors = @[device[@"palette"][@"base"] ?: @"", device[@"palette"][@"accent"] ?: @""];
    NSString *presetName = @"Personnalisée";
    for (NSString *name in [self devicePalettePresets]) if ([[self devicePalettePresets][name] isEqual:colors]) { presetName = name; break; }
    [self.devicePaletteMenu selectItemWithTitle:presetName];
    self.deviceTestProgramField.stringValue = @"81";
    self.deviceConfigStatus.stringValue = [NSString stringWithFormat:@"MIDI · Program Change · canal %@ · ID non modifiable", self.deviceChannelField.stringValue];
}

- (NSArray<NSString *> *)cleanAliasesFromString:(NSString *)value {
    NSMutableOrderedSet *aliases = [NSMutableOrderedSet orderedSet];
    for (NSString *part in [value componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]]) {
        NSString *alias = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (alias.length) [aliases addObject:alias];
    }
    return aliases.array;
}

- (NSString *)validateDeviceProfiles {
    NSMutableSet *ids = [NSMutableSet set], *enabledChannels = [NSMutableSet set];
    BOOL hasA = NO, hasB = NO;
    NSRegularExpression *color = [NSRegularExpression regularExpressionWithPattern:@"^#[0-9A-Fa-f]{6}$" options:0 error:nil];
    for (NSDictionary *device in self.deviceProfiles) {
        NSString *deviceID = device[@"id"], *name = [device[@"display_name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!deviceID.length || [ids containsObject:deviceID]) return @"Chaque ID interne doit être unique";
        [ids addObject:deviceID]; hasA |= [deviceID isEqualToString:@"console_a"]; hasB |= [deviceID isEqualToString:@"console_b"];
        if (!name.length) return [NSString stringWithFormat:@"%@ : nom affiché obligatoire", deviceID];
        NSInteger channel = [device[@"midi_channel"] integerValue];
        if (channel < 1 || channel > 16) return [NSString stringWithFormat:@"%@ : canal MIDI attendu entre 1 et 16", name];
        NSDictionary *palette = device[@"palette"];
        for (NSString *key in @[@"base", @"accent"]) if ([color numberOfMatchesInString:palette[key] ?: @"" options:0 range:NSMakeRange(0, [palette[key] length]) ] != 1) return [NSString stringWithFormat:@"%@ : palette invalide", name];
        if ([device[@"enabled"] boolValue]) {
            if (![[device[@"protocol"] lowercaseString] isEqualToString:@"midi"] || ![[device[@"signal_type"] lowercaseString] isEqualToString:@"program_change"]) return [NSString stringWithFormat:@"%@ : handler bientôt disponible", name];
            if (![device[@"ableton_track_aliases"] count]) return [NSString stringWithFormat:@"%@ : au moins un alias Ableton est requis", name];
            NSNumber *channelNumber = @(channel); if ([enabledChannels containsObject:channelNumber]) return [NSString stringWithFormat:@"%@ : collision de canal MIDI", name]; [enabledChannels addObject:channelNumber];
        }
    }
    return hasA && hasB ? nil : @"console_a et console_b doivent être conservés";
}

- (BOOL)commitVisibleDeviceFields {
    NSMutableDictionary *device = [self selectedDeviceProfile]; if (!device) return NO;
    NSString *name = [self.deviceNameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *aliases = [self cleanAliasesFromString:self.deviceAliasesField.stringValue];
    device[@"display_name"] = name; device[@"enabled"] = @(self.deviceEnabledCheck.state == NSControlStateValueOn);
    device[@"midi_channel"] = @(self.deviceChannelField.integerValue); device[@"ableton_track_aliases"] = aliases;
    device[@"visibility"] = @{ @"show_control": @(self.deviceShowCheck.state == NSControlStateValueOn), @"remote": @(self.deviceRemoteCheck.state == NSControlStateValueOn), @"network_manager": @(self.deviceNetworkCheck.state == NSControlStateValueOn) };
    NSString *preset = self.devicePaletteMenu.titleOfSelectedItem;
    NSArray *colors = [self devicePalettePresets][preset];
    if (colors) device[@"palette"] = @{ @"base": colors[0], @"accent": colors[1] };
    NSString *error = [self validateDeviceProfiles];
    if (error.length) { self.deviceConfigStatus.stringValue = error; self.deviceConfigStatus.textColor = NSColor.systemRedColor; return NO; }
    return YES;
}

- (void)saveDeviceProfiles:(id)sender {
    (void)sender; if (![self commitVisibleDeviceFields]) return;
    NSDictionary *payload = @{ @"schema_version": @(CLDeviceSchemaVersion), @"profile_id": @"default", @"profile_name": @"Configuration personnalisée", @"devices": self.deviceProfiles };
    NSError *error = nil; NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    NSString *path = CLDeviceConfigurationPath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
    BOOL saved = data && [data writeToFile:path options:NSDataWritingAtomic error:&error];
    [self refreshDeviceProfileMenuSelectingID:[self selectedDeviceProfile][@"id"]];
    self.deviceConfigStatus.textColor = saved ? [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0] : NSColor.systemRedColor;
    self.deviceConfigStatus.stringValue = saved ? @"Configuration enregistrée · redémarrage requis" : [NSString stringWithFormat:@"Enregistrement impossible : %@", error.localizedDescription ?: @"erreur"];
}

- (void)restoreDefaultDeviceProfiles:(id)sender {
    (void)sender; NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Restaurer CL5 / QL1 par défaut ?"; alert.informativeText = @"Les réglages MIDI système, RTP et bibliothèques CLF ne seront pas modifiés."; [alert addButtonWithTitle:@"Restaurer"]; [alert addButtonWithTitle:@"Annuler"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.deviceProfiles = [NSMutableArray array]; for (NSDictionary *device in [self defaultDeviceConfigurationPayload][@"devices"]) [self.deviceProfiles addObject:[device mutableCopy]];
    [self refreshDeviceProfileMenuSelectingID:@"console_a"]; self.deviceConfigStatus.stringValue = @"Valeurs par défaut prêtes · Enregistrer pour confirmer";
}

- (void)addDeviceProfile:(id)sender {
    (void)sender; NSUInteger index = 3; NSMutableSet *ids = [NSMutableSet set]; for (NSDictionary *device in self.deviceProfiles) [ids addObject:device[@"id"]]; while ([ids containsObject:[NSString stringWithFormat:@"device_%lu", (unsigned long)index]]) index++;
    NSString *deviceID = [NSString stringWithFormat:@"device_%lu", (unsigned long)index];
    NSMutableDictionary *device = [@{ @"id": deviceID, @"display_name": @"Nouveau device", @"enabled": @NO, @"device_type": @"console", @"protocol": @"midi", @"signal_type": @"program_change", @"midi_channel": @3, @"ableton_track_aliases": @[@"NOUVEAU DEVICE PROGRAM"], @"palette": @{ @"base": @"#79B8FF", @"accent": @"#397FD1" }, @"library": NSNull.null, @"legacy_key": NSNull.null, @"visibility": @{ @"show_control": @YES, @"remote": @YES, @"network_manager": @YES }, @"tx": @{ @"enabled": @YES }, @"rx": @{ @"enabled": @YES } } mutableCopy];
    [self.deviceProfiles addObject:device]; [self refreshDeviceProfileMenuSelectingID:deviceID]; self.deviceConfigStatus.stringValue = @"Nouveau device désactivé · non relié à la production";
}

- (void)deleteDeviceProfile:(id)sender {
    (void)sender; NSMutableDictionary *device = [self selectedDeviceProfile]; NSString *deviceID = device[@"id"];
    if ([deviceID isEqualToString:@"console_a"] || [deviceID isEqualToString:@"console_b"]) { self.deviceConfigStatus.stringValue = @"Les devices historiques peuvent être désactivés, pas supprimés"; return; }
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = [NSString stringWithFormat:@"Supprimer %@ ?", device[@"display_name"]]; [alert addButtonWithTitle:@"Supprimer"]; [alert addButtonWithTitle:@"Annuler"];
    if ([alert runModal] == NSAlertFirstButtonReturn) { [self.deviceProfiles removeObject:device]; [self refreshDeviceProfileMenuSelectingID:@"console_a"]; }
}

- (void)deviceProfileChanged:(id)sender { (void)sender; [self populateDeviceEditorFields]; }
- (void)devicePaletteChanged:(id)sender { (void)sender; self.deviceConfigStatus.stringValue = @"Palette d’identité sélectionnée · état visuel inchangé"; }

- (void)refreshIsolatedDeviceTestEndpoints:(id)sender {
    (void)sender;
    [self.deviceTestDestinationMenu removeAllItems]; [self.deviceTestSourceMenu removeAllItems];
    for (NSString *name in EndpointNames(NO)) if (!CLIsProtectedDeviceTestEndpoint(name)) [self.deviceTestDestinationMenu addItemWithTitle:name];
    for (NSString *name in EndpointNames(YES)) if (!CLIsProtectedDeviceTestEndpoint(name)) [self.deviceTestSourceMenu addItemWithTitle:name];
    if (!self.deviceTestDestinationMenu.numberOfItems) [self.deviceTestDestinationMenu addItemWithTitle:@"Aucune destination de test sûre"];
    if (!self.deviceTestSourceMenu.numberOfItems) [self.deviceTestSourceMenu addItemWithTitle:@"Aucune source de test sûre"];
}

- (void)startIsolatedDeviceTestRX:(id)sender {
    (void)sender; NSString *name = self.deviceTestSourceMenu.titleOfSelectedItem;
    if (CLIsProtectedDeviceTestEndpoint(name) || [name hasPrefix:@"Aucune"]) { self.deviceTestResult.stringValue = @"TEST RX refusé · endpoint protégé ou absent"; return; }
    if (!self.deviceTestClient) MIDIClientCreate(CFSTR("CL Device Test Bench"), NULL, NULL, &_deviceTestClient);
    if (!self.deviceTestInputPort) MIDIInputPortCreate(self.deviceTestClient, CFSTR("Isolated test RX"), CLIsolatedDeviceTestRead, (__bridge void *)self, &_deviceTestInputPort);
    if (self.deviceTestSource) MIDIPortDisconnectSource(self.deviceTestInputPort, self.deviceTestSource);
    self.deviceTestSource = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) { MIDIEndpointRef source = MIDIGetSource(index); if ([EndpointName(source) isEqualToString:name]) { self.deviceTestSource = source; break; } }
    OSStatus status = self.deviceTestSource ? MIDIPortConnectSource(self.deviceTestInputPort, self.deviceTestSource, (void *)(uintptr_t)self.deviceTestSource) : -1;
    self.deviceTestResult.stringValue = status == noErr ? [NSString stringWithFormat:@"TEST RX écoute %@ · état production non connecté", name] : @"TEST RX impossible";
}

- (void)sendIsolatedDeviceTestTX:(id)sender {
    (void)sender; NSDictionary *device = [self selectedDeviceProfile]; NSString *destinationName = self.deviceTestDestinationMenu.titleOfSelectedItem;
    NSInteger memory = self.deviceTestProgramField.integerValue, channel = [device[@"midi_channel"] integerValue];
    if (CLIsProtectedDeviceTestEndpoint(destinationName) || [destinationName hasPrefix:@"Aucune"] || memory < 1 || memory > 128) { self.deviceTestResult.stringValue = @"TEST TX refusé · destination protégée ou valeur invalide"; return; }
    MIDIEndpointRef destination = 0; for (ItemCount index = 0; index < MIDIGetNumberOfDestinations(); index++) { MIDIEndpointRef item = MIDIGetDestination(index); if ([EndpointName(item) isEqualToString:destinationName]) { destination = item; break; } }
    if (!self.deviceTestClient) MIDIClientCreate(CFSTR("CL Device Test Bench"), NULL, NULL, &_deviceTestClient);
    if (!self.deviceTestOutputPort) MIDIOutputPortCreate(self.deviceTestClient, CFSTR("Isolated test TX"), &_deviceTestOutputPort);
    Byte buffer[128]; MIDIPacketList *packets = (MIDIPacketList *)buffer; MIDIPacket *packet = MIDIPacketListInit(packets); UInt8 bytes[2] = {(UInt8)(0xC0 | ((channel - 1) & 0x0F)), (UInt8)(memory - 1)}; packet = MIDIPacketListAdd(packets, sizeof(buffer), packet, 0, 2, bytes);
    OSStatus status = destination && packet ? MIDISend(self.deviceTestOutputPort, destination, packets) : -1;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970; self.deviceTestSent = @{ @"device_id": device[@"id"], @"channel": @(channel), @"midi_program": @(memory - 1), @"timestamp": @(now), @"destination": destinationName };
    self.deviceTestResult.stringValue = status == noErr ? [NSString stringWithFormat:@"TEST TX · Ch.%ld · raw %ld · mémoire %ld · %@", (long)channel, (long)(memory - 1), (long)memory, destinationName] : @"TEST TX échec CoreMIDI";
}

- (void)runIsolatedDeviceRoundTrip:(id)sender { [self startIsolatedDeviceTestRX:nil]; [self sendIsolatedDeviceTestTX:nil]; self.deviceTestResult.stringValue = [@"ROUND TRIP TEST · " stringByAppendingString:self.deviceTestResult.stringValue]; }

- (void)recordIsolatedDeviceTestProgram:(UInt8)program channel:(UInt8)channel source:(NSString *)source {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970; self.deviceTestReceived = @{ @"channel": @(channel), @"midi_program": @(program), @"timestamp": @(now), @"source": source ?: @"" };
    NSNumber *sentProgram = self.deviceTestSent[@"midi_program"], *sentChannel = self.deviceTestSent[@"channel"];
    BOOL match = sentProgram && sentProgram.unsignedCharValue == program && sentChannel.unsignedCharValue == channel;
    NSTimeInterval latency = self.deviceTestSent ? (now - [self.deviceTestSent[@"timestamp"] doubleValue]) * 1000.0 : 0;
    self.deviceTestResult.stringValue = [NSString stringWithFormat:@"TEST RX · %@ · Ch.%u · raw %u · mémoire %u · %@%@", source, channel, program, program + 1, self.deviceTestSent ? (match ? @"MATCH" : @"MISMATCH") : @"OBSERVÉ", self.deviceTestSent ? [NSString stringWithFormat:@" · %.1f ms", latency] : @""];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.devicesWindow) self.devicesWindow = nil;
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
    [self.modeSyncTimer invalidate];
    [self.serviceBrowser stop];
    [self.agentServiceBrowser stop];
    if (self.guardianTask.running) [self.guardianTask terminate];
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
    }
    if (self.returnMonitorInputPort) MIDIPortDispose(self.returnMonitorInputPort);
    if (self.returnMonitorClient) MIDIClientDispose(self.returnMonitorClient);
    if (self.deviceTestSource && self.deviceTestInputPort) MIDIPortDisconnectSource(self.deviceTestInputPort, self.deviceTestSource);
    if (self.deviceTestInputPort) MIDIPortDispose(self.deviceTestInputPort);
    if (self.deviceTestOutputPort) MIDIPortDispose(self.deviceTestOutputPort);
    if (self.deviceTestClient) MIDIClientDispose(self.deviceTestClient);
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

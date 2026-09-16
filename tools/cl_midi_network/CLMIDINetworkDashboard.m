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
static NSString *const CLDeviceTestRXDiagnosticPath = @"/private/tmp/CL_MIDI_TEST_BENCH_RX.log";

static void CLDeviceTestRXDiagnostic(NSString *event, NSString *detail) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", event ?: @"TEST_BENCH_EVENT", detail ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized(NSFileHandle.class) {
        if (![NSFileManager.defaultManager fileExistsAtPath:CLDeviceTestRXDiagnosticPath]) {
            [data writeToFile:CLDeviceTestRXDiagnosticPath atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CLDeviceTestRXDiagnosticPath];
        [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile];
    }
}

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

static NSString *CLMIDIStringProperty(MIDIObjectRef object, CFStringRef property) {
    CFStringRef value = NULL;
    if (!object || MIDIObjectGetStringProperty(object, property, &value) != noErr || !value) return @"";
    return CFBridgingRelease(value) ?: @"";
}

static SInt32 CLMIDIIntegerProperty(MIDIObjectRef object, CFStringRef property, SInt32 fallback) {
    SInt32 value = fallback;
    return object && MIDIObjectGetIntegerProperty(object, property, &value) == noErr ? value : fallback;
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

static NSPasteboardType const CLSimulatorRowPasteboardType = @"com.cl-audio-controller.simulator-row";

@protocol CLSimulatorRowReordering <NSObject>
- (void)moveSimulatorChannel:(NSInteger)midiChannel toDisplayIndex:(NSUInteger)displayIndex;
@end

@interface CLSimulatorDragButton : NSButton <NSDraggingSource>
@property NSInteger midiChannel;
@end

@implementation CLSimulatorDragButton
- (void)mouseDragged:(NSEvent *)event {
    NSPasteboardItem *pasteboardItem = [[NSPasteboardItem alloc] init];
    [pasteboardItem setString:[NSString stringWithFormat:@"%ld", (long)self.midiChannel]
                      forType:CLSimulatorRowPasteboardType];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(24, 22)];
    [image lockFocus];
    [@"⠿" drawAtPoint:NSMakePoint(4, 2) withAttributes:@{NSForegroundColorAttributeName: NSColor.labelColor}];
    [image unlockFocus];
    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboardItem];
    [draggingItem setDraggingFrame:self.bounds contents:image];
    [self beginDraggingSessionWithItems:@[draggingItem] event:event source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session; (void)context; return NSDragOperationMove;
}
@end

@interface CLSimulatorRowsView : NSStackView <NSDraggingDestination>
@property (weak) id<CLSimulatorRowReordering> reorderDelegate;
@end

@implementation CLSimulatorRowsView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self registerForDraggedTypes:@[CLSimulatorRowPasteboardType]];
    return self;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { (void)sender; return NSDragOperationMove; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSInteger channel = [[sender.draggingPasteboard stringForType:CLSimulatorRowPasteboardType] integerValue];
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSUInteger index = 0;
    for (NSView *row in self.arrangedSubviews) {
        if (point.y < NSMidY(row.frame)) break;
        index += 1;
    }
    if ([self.reorderDelegate respondsToSelector:@selector(moveSimulatorChannel:toDisplayIndex:)])
        [self.reorderDelegate moveSimulatorChannel:channel toDisplayIndex:index];
    return YES;
}
@end

@interface CLNetworkDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate, CLSimulatorRowReordering>
@property NSWindow *window;
@property NSView *headerPanel;
@property NSView *statusPanel;
@property NSView *targetPanel;
@property NSTextField *generalModeTitleLabel;
@property NSView *testPanel;
@property NSTextField *rtpTestTitle;
@property NSView *technicalPanel;
@property NSView *consoleLibrariesPanel;
@property NSView *programChangeReturnsPanel;
@property NSMutableDictionary<NSString *, NSDictionary *> *programChangeReturnViews;
@property NSTextField *consoleLibrariesMode;
@property NSTextField *backendCompactStatus;
@property NSTextField *simulatorCompactStatus;
@property NSInteger simulatorAutoRestoreAttempts;
@property NSScrollView *consoleLibrariesScroll;
@property NSMutableDictionary<NSString *, NSTextField *> *consoleLibraryNameLabels;
@property NSMutableDictionary<NSString *, NSTextField *> *consoleLibraryStateLabels;
@property NSTextField *appTitleLabel;
@property NSTextField *appSubtitleLabel;
@property NSTextField *compactSummary;
@property NSTextField *footerLabel;
@property NSButton *showModeButton;
@property NSButton *devicesButton;
@property NSButton *assistantDevicesButton;
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
@property NSTextField *operatingModeReasonLabel;
@property NSTextField *localRTPNoteLabel;
@property NSTextField *localRTPDetailLabel;
@property NSTextField *programField;
@property NSPopUpButton *testTargetMenu;
@property NSButton *testButton;
@property NSPopUpButton *targetMenu;
@property NSButton *connectButton;
@property NSTextField *remoteTargetTitleLabel;
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
@property NSWindow *simulatorWindow;
@property NSButton *simulatorWindowButton;
@property NSTextField *simulatorModeLabel;
@property NSPopUpButton *simulatorEndpointMenu;
@property NSPopUpButton *simulatorInputEndpointMenu;
@property NSTextField *simulatorDelayField;
@property NSTextField *simulatorStatusLabel;
@property NSTextField *simulatorActivityLabel;
@property NSButton *simulatorStartButton;
@property NSButton *simulatorStopAllButton;
@property NSTextField *simulatorCL5MemoryField;
@property NSTextField *simulatorQL1MemoryField;
@property NSMutableArray<NSMutableDictionary *> *simulatorDevices;
@property NSMutableDictionary<NSString *, NSTask *> *simulatorTasks;
@property NSMutableDictionary<NSString *, NSMutableData *> *simulatorOutputBuffers;
@property NSScrollView *simulatorDevicesScroll;
@property NSStackView *simulatorDeviceRows;
@property NSMutableDictionary<NSString *, NSTextField *> *simulatorMemoryFields;
@property NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSTextField *> *> *simulatorValueFields;
@property NSMutableArray<NSNumber *> *simulatorDisplayOrder;
@property NSMutableSet<NSNumber *> *simulatorHiddenChannels;
@property NSMutableDictionary<NSNumber *, NSString *> *simulatorGenericSignalTypes;
@property NSPopUpButton *simulatorVisibilityMenu;
@property NSTextView *simulatorJournalView;
@property NSMutableArray<NSString *> *simulatorJournalEvents;
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
@property NSTextField *assistantDevicesTitleLabel;
@property NSView *assistantTestBanner;
@property NSTextField *assistantTestStatusLabel;
@property NSButton *assistantStopTestsButton;
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
@property MIDIClientRef simulatorMidiClient;
@property MIDIPortRef simulatorMidiOutputPort;
@property MIDIEndpointRef localReturnDestination;
@property BOOL publishedLocalReturnAvailable;
@property BOOL localReturnMode;
@property BOOL operatingModeChangeInFlight;
@property BOOL operatingModeSyncInFlight;
@property BOOL endpointRefreshInFlight;
@property BOOL showControlAvailable;
@property NSString *transportHeadline;
@property NSString *transportDetail;
@property MIDIPortRef expectedMonitorInputPort;
@property MIDIEndpointRef expectedMonitorSource;
@property NSString *expectedMonitorSourceName;
@property OSStatus expectedMonitorStatus;
@property MIDIPortRef returnMonitorInputPort;
@property MIDIEndpointRef returnMonitorSource;
@property NSString *returnMonitorSourceName;
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
@property NSPopUpButton *deviceSignalMenu;
@property NSTextField *deviceLibraryField;
@property NSTextField *deviceLibraryHint;
@property NSButton *deviceEnabledCheck;
@property NSButton *deviceShowCheck;
@property NSButton *deviceRemoteCheck;
@property NSButton *deviceNetworkCheck;
@property NSButton *deviceTXCheck;
@property NSButton *deviceRXCheck;
@property NSTextField *deviceConfigStatus;
@property NSPopUpButton *deviceTestDestinationMenu;
@property NSPopUpButton *deviceTestSourceMenu;
@property NSTextField *deviceTestProgramField;
@property NSTextField *deviceTestValueField;
@property NSTextField *deviceTestParameterLabel;
@property NSTextField *deviceTestValueLabel;
@property NSTextField *deviceTestResult;
@property MIDIClientRef deviceTestClient;
@property MIDIPortRef deviceTestOutputPort;
@property MIDIPortRef deviceTestInputPort;
@property MIDIEndpointRef deviceTestSource;
@property UInt8 deviceTestRunningStatus;
@property UInt8 deviceTestDataByte;
@property BOOL deviceTestHasDataByte;
@property NSString *deviceTestSourceName;
@property NSDictionary *deviceTestSent;
@property NSDictionary *deviceTestReceived;
@property BOOL deviceRoundTripPending;
@property NSUInteger deviceRoundTripGeneration;
@property NSWindow *midiInventoryWindow;
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
- (void)updateSimulatorCompactStatus;
- (void)restorePersistedSimulatorAutoDevices;
- (void)rebuildConsoleLibraryRows;
- (void)rebuildProgramChangeReturnCards;
- (void)refreshProfileDrivenViews;
- (void)updateConsoleLibrariesFromStatus:(NSDictionary *)status;
- (void)recordIsolatedDeviceTestProgram:(UInt8)program channel:(UInt8)channel source:(NSString *)source;
- (void)recordIsolatedDeviceTestMessageType:(NSString *)type channel:(UInt8)channel data1:(UInt8)data1 data2:(NSInteger)data2 source:(NSString *)source;

- (void)rebuildReturnDeviceRouting;
- (void)updateAssistantPrimaryStatus;
- (void)applyEndpointSnapshotWithSources:(NSArray<NSString *> *)sources destinations:(NSArray<NSString *> *)destinations;
@end

static NSString *const CLExpectedEndpointName = @"Gestionnaire IAC Bus 1";
static NSString *const CLLocalReturnEndpointName = @"CL MIDI Return Test";
// CL_LOCAL_RETURN_ENDPOINT_ALLOW_V1
static NSString *const CLRTPReturnEndpointName = @"Réseau RTP MB Chris";
static NSString *const CLConsoleReturnEndpointPreference = @"consoleReturnEndpoint";
static NSString *const CLLocalSimulatorDestinationPreference = @"simulatorMidiDestination";
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

static NSString *CLPreferredLocalSimulatorDestination(NSArray<NSString *> *destinations) {
    for (NSString *name in destinations) {
        if ([name rangeOfString:@"IAC" options:NSCaseInsensitiveSearch].location != NSNotFound)
            return name;
    }
    return destinations.firstObject;
}

static NSString *CLProtectedDeviceTestEndpointReason(NSString *name) {
    if ([name isEqualToString:CLExpectedEndpointName]) return @"EXPECTED réservé au show";
    if ([name isEqualToString:CLLocalReturnEndpointName]) return @"RETURNED réservé au show";
    if (CLIsRTPReturnEndpointName(name)) return @"RTP protégé pour éviter la pollution du spectacle";
    return @"";
}

static NSString *CLMIDIEndpointTransport(NSString *name, NSString *manufacturer, NSString *model, NSString *driverOwner, BOOL hasDevice) {
    NSString *evidence = [[NSString stringWithFormat:@"%@ %@ %@ %@", name ?: @"", manufacturer ?: @"", model ?: @"", driverOwner ?: @""] lowercaseString];
    if (CLIsRTPReturnEndpointName(name) || [evidence containsString:@"applemidirtp"]) return @"RTP";
    if ([evidence containsString:@"iac"]) return @"IAC";
    if ([evidence containsString:@"usb"] || [evidence containsString:@"appleusbaudio"]) return @"USB";
    return hasDevice ? @"MIDI" : @"virtuel";
}

static NSArray<NSDictionary *> *CLAllMIDIEndpointInventory(void) {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSNumber *sourceFlag in @[@YES, @NO]) {
        BOOL source = sourceFlag.boolValue;
        ItemCount count = source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
        for (ItemCount index = 0; index < count; index++) {
            MIDIEndpointRef endpoint = source ? MIDIGetSource(index) : MIDIGetDestination(index);
            MIDIEntityRef entity = 0; MIDIDeviceRef device = 0;
            MIDIEndpointGetEntity(endpoint, &entity);
            if (entity) MIDIEntityGetDevice(entity, &device);
            NSString *name = EndpointName(endpoint);
            NSString *manufacturer = CLMIDIStringProperty(device ?: entity ?: endpoint, kMIDIPropertyManufacturer);
            NSString *model = CLMIDIStringProperty(device ?: entity ?: endpoint, kMIDIPropertyModel);
            NSString *driverOwner = CLMIDIStringProperty(device ?: entity ?: endpoint, kMIDIPropertyDriverOwner);
            NSString *reason = CLProtectedDeviceTestEndpointReason(name);
            NSString *entityName = entity ? CLMIDIStringProperty(entity, kMIDIPropertyDisplayName) : @"";
            NSString *deviceName = device ? CLMIDIStringProperty(device, kMIDIPropertyDisplayName) : @"";
            if (!entityName.length && entity) entityName = CLMIDIStringProperty(entity, kMIDIPropertyName);
            if (!deviceName.length && device) deviceName = CLMIDIStringProperty(device, kMIDIPropertyName);
            [rows addObject:@{
                @"name": name.length ? name : @"<sans nom>", @"direction": source ? @"Source RX" : @"Destination TX",
                @"unique_id": @(CLMIDIIntegerProperty(endpoint, kMIDIPropertyUniqueID, 0)),
                @"online": @(CLMIDIIntegerProperty(endpoint, kMIDIPropertyOffline, 0) == 0),
                @"entity": entityName ?: @"", @"device": deviceName ?: @"",
                @"manufacturer": manufacturer, @"model": model, @"driver": driverOwner,
                @"transport": CLMIDIEndpointTransport(name, manufacturer, model, driverOwner, device != 0),
                @"protected": @(reason.length > 0), @"reason": reason
            }];
        }
    }
    return rows;
}

static void CLDeviceTestMIDINotify(const MIDINotification *message, void *refCon) {
    if (message->messageID != kMIDIMsgObjectAdded && message->messageID != kMIDIMsgObjectRemoved && message->messageID != kMIDIMsgSetupChanged) return;
    CLNetworkDelegate *delegate = (__bridge CLNetworkDelegate *)refCon;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (delegate.devicesWindow) [delegate performSelector:@selector(refreshIsolatedDeviceTestEndpoints:) withObject:nil];
    });
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
    MIDIEndpointRef callbackSource = (MIDIEndpointRef)(uintptr_t)srcConnRefCon;
    NSString *sourceName = delegate.deviceTestSourceName ?: @"Source RX isolée";
    UInt8 runningStatus = delegate.deviceTestRunningStatus;
    UInt8 dataByte = delegate.deviceTestDataByte;
    BOOL hasDataByte = delegate.deviceTestHasDataByte;

    CLDeviceTestRXDiagnostic(@"RX_CALLBACK_ENTER",
        [NSString stringWithFormat:@"packets=%u source_ref=%u source_name=%@ running_before=%02X",
         (unsigned)packetList->numPackets, (unsigned)callbackSource, sourceName, runningStatus]);

    const MIDIPacket *packet = &packetList->packet[0];

    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        NSMutableString *hex = [NSMutableString string];
        for (UInt16 i = 0; i < packet->length; i++)
            [hex appendFormat:i ? @" %02X" : @"%02X", packet->data[i]];

        CLDeviceTestRXDiagnostic(@"RX_PACKET",
            [NSString stringWithFormat:@"index=%u length=%u bytes=%@ running_before=%02X",
             (unsigned)packetIndex, (unsigned)packet->length, hex, runningStatus]);

        for (UInt16 index = 0; index < packet->length; index++) {
            UInt8 byte = packet->data[index];

            // Realtime MIDI n'annule ni running status ni message partiel.
            if (byte >= 0xF8) continue;

            if (byte & 0x80) {
                if (byte < 0xF0) {
                    runningStatus = byte;
                    hasDataByte = NO;
                } else {
                    runningStatus = 0;
                    hasDataByte = NO;
                }
                continue;
            }

            UInt8 family = runningStatus & 0xF0;
            UInt8 channel = (runningStatus & 0x0F) + 1;

            // Program Change : un seul octet de données.
            if (family == 0xC0) {
                UInt8 program = byte;
                CLDeviceTestRXDiagnostic(@"RX_PROGRAM_CHANGE",
                    [NSString stringWithFormat:@"channel=%u raw=%u memory=%u source=%@",
                     channel, program, program + 1, sourceName]);

                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate recordIsolatedDeviceTestMessageType:@"program_change"
                                                          channel:channel
                                                            data1:program
                                                            data2:-1
                                                           source:sourceName];
                });
                continue;
            }

            // Channel Pressure : un octet, non utilisé par le Test Bench.
            if (family == 0xD0) continue;

            // Les autres messages Channel Voice utilisent deux data bytes.
            if (!hasDataByte) {
                dataByte = byte;
                hasDataByte = YES;
                continue;
            }

            UInt8 data1 = dataByte;
            UInt8 data2 = byte;
            hasDataByte = NO;

            NSString *messageType = nil;
            if (family == 0xB0) {
                messageType = @"control_change";
            } else if (family == 0x90) {
                messageType = data2 == 0 ? @"note_off" : @"note_on";
            } else if (family == 0x80) {
                messageType = @"note_off";
            }

            if (messageType) {
                CLDeviceTestRXDiagnostic(@"RX_GENERIC_MESSAGE",
                    [NSString stringWithFormat:@"type=%@ channel=%u data1=%u data2=%u source=%@",
                     messageType, channel, data1, data2, sourceName]);

                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate recordIsolatedDeviceTestMessageType:messageType
                                                          channel:channel
                                                            data1:data1
                                                            data2:data2
                                                           source:sourceName];
                });
            }
        }

        packet = MIDIPacketNext(packet);
    }

    delegate.deviceTestRunningStatus = runningStatus;
    delegate.deviceTestDataByte = dataByte;
    delegate.deviceTestHasDataByte = hasDataByte;

    CLDeviceTestRXDiagnostic(@"RX_CALLBACK_EXIT",
        [NSString stringWithFormat:@"running_after=%02X partial=%d data1=%u",
         runningStatus, hasDataByte, dataByte]);
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
    BOOL verificationBundle = [NSBundle.mainBundle.bundleIdentifier hasSuffix:@".verification"];
    if (runningFromAppBundle && !verificationBundle) {
        [self installBackgroundLaunchAgent];
    } else {
        CLAppendDiagnostic(@"background-monitor-not-installed", verificationBundle
            ? @"bundle Verification isolé : LaunchAgent de production inchangé"
            : @"mode développement : LaunchAgent non installé");
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

    NSView *header = self.headerPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 756, 468, 64)];
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

    NSImageView *logoView = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 6, 444, 52)];
    logoView.image = logo;
    logoView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [header addSubview:logoView];
    NSTextField *appTitle = self.appTitleLabel = [self label:@"CL MIDI NETWORK MANAGER" frame:NSMakeRect(20, 704, 220, 24) size:15 bold:YES];
    NSTextField *appSubtitle = self.appSubtitleLabel = [self label:@"" frame:NSMakeRect(0, 0, 1, 1) size:9 bold:NO];
    appSubtitle.hidden = YES;
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
    self.showModeButton = [self accentButton:@"Diagnostic détaillé" frame:NSMakeRect(360, 701, 124, 30) action:@selector(toggleShowMode:) color:[NSColor colorWithRed:0.24 green:0.28 blue:0.35 alpha:1.0]];
    [content addSubview:self.showModeButton];

    NSView *statusPanel = self.statusPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 626, 468, 62)];
    statusPanel.wantsLayer = YES; statusPanel.layer.cornerRadius = 12; statusPanel.layer.borderWidth = 1;
    statusPanel.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.075 blue:0.095 alpha:1.0].CGColor;
    statusPanel.layer.borderColor = [NSColor colorWithRed:0.22 green:0.55 blue:0.78 alpha:0.7].CGColor;
    [content addSubview:statusPanel];
    self.lamp = [[NSView alloc] initWithFrame:NSMakeRect(18, 23, 16, 16)];
    self.lamp.wantsLayer = YES;
    self.lamp.layer.cornerRadius = 8;
    [statusPanel addSubview:self.lamp];
    self.headline = [self label:@"Analyse de la connexion RTP…" frame:NSMakeRect(48, 32, 245, 20) size:14 bold:YES];
    self.detail = [self label:@"" frame:NSMakeRect(48, 9, 400, 18) size:10 bold:NO];
    [statusPanel addSubview:self.headline];
    [statusPanel addSubview:self.detail];

    self.backendCompactStatus =
        [self label:@"● BACKEND · …"
              frame:NSMakeRect(294, 33, 154, 18)
               size:8
               bold:YES];
    self.backendCompactStatus.alignment = NSTextAlignmentRight;
    self.backendCompactStatus.textColor = NSColor.secondaryLabelColor;
    [statusPanel addSubview:self.backendCompactStatus];

    self.simulatorCompactStatus =
        [self label:@"● RETOURS AUTO 0/0"
              frame:NSMakeRect(294, 10, 154, 16)
               size:8
               bold:YES];
    self.simulatorCompactStatus.alignment = NSTextAlignmentRight;
    self.simulatorCompactStatus.textColor = NSColor.secondaryLabelColor;
    [statusPanel addSubview:self.simulatorCompactStatus];

    // Laisser la place au deuxième indicateur à droite.
    self.detail.frame = NSMakeRect(48, 9, 238, 18);

    NSView *targetPanel = self.targetPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 543, 468, 100)];
    targetPanel.wantsLayer = YES; targetPanel.layer.cornerRadius = 12; targetPanel.layer.borderWidth = 1;
    targetPanel.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.088 blue:0.11 alpha:1.0].CGColor;
    targetPanel.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor; [content addSubview:targetPanel];
    self.generalModeTitleLabel = [self label:@"MODE GÉNÉRAL" frame:NSMakeRect(16, 68, 150, 20) size:10 bold:YES];
    [targetPanel addSubview:self.generalModeTitleLabel];
    self.remoteTargetTitleLabel = [self label:@"CIBLE ABLETON DISTANTE (RTP)" frame:NSMakeRect(194, 68, 210, 20) size:10 bold:YES];
    [targetPanel addSubview:self.remoteTargetTitleLabel];
    self.returnModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 28, 168, 34) pullsDown:NO];
    [self.returnModeMenu addItemsWithTitles:@[@"Ableton local", @"Ableton distant"]];
    self.returnModeMenu.target = self;
    self.returnModeMenu.action = @selector(returnModeChanged:);
    NSString *savedReturnMode = [NSUserDefaults.standardUserDefaults stringForKey:@"consoleReturnMode"];
    [self.returnModeMenu selectItemAtIndex:[savedReturnMode isEqualToString:@"rtp_remote"] ? 1 : 0];
    self.localReturnMode = self.returnModeMenu.indexOfSelectedItem == 0;
    [self stylePopup:self.returnModeMenu accent:[NSColor colorWithRed:0.58 green:0.34 blue:0.19 alpha:1.0]];
    [targetPanel addSubview:self.returnModeMenu];
    self.targetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(194, 28, 166, 34) pullsDown:NO];
    self.targetMenu.target = self;
    self.targetMenu.action = @selector(targetChanged:);
    [self.targetMenu addItemWithTitle:@"Recherche des correspondants…"];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    [targetPanel addSubview:self.targetMenu];
    self.connectButton = [self accentButton:@"Connecter" frame:NSMakeRect(370, 27, 82, 36) action:@selector(connectSelectedPeer:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.82 alpha:1.0]];
    self.targetMenu.enabled = !self.localReturnMode;
    self.connectButton.enabled = !self.localReturnMode;
    self.connectButton.title = self.localReturnMode ? @"Non requis" : @"Connecter";
    self.connectButton.toolTip = self.localReturnMode
        ? @"Aucune connexion RTP n’est requise en mode Ableton local."
        : @"Recherche d’une cible RTP distante en cours.";
    [targetPanel addSubview:self.connectButton];
    self.operatingModeReasonLabel = [self label:@"Mode conservé depuis la dernière configuration appliquée" frame:NSMakeRect(16, 6, 436, 18) size:8 bold:NO];
    self.operatingModeReasonLabel.textColor = [NSColor colorWithWhite:0.67 alpha:1.0];
    self.operatingModeReasonLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [targetPanel addSubview:self.operatingModeReasonLabel];
    self.localRTPNoteLabel = [self label:@"RTP non requis" frame:NSMakeRect(294, 29, 158, 16) size:10 bold:YES];
    self.localRTPNoteLabel.textColor = [NSColor colorWithRed:0.42 green:0.80 blue:0.75 alpha:1.0];
    self.localRTPNoteLabel.hidden = !self.localReturnMode;
    [targetPanel addSubview:self.localRTPNoteLabel];
    self.localRTPDetailLabel = [self label:@"Retour MIDI local via port dédié." frame:NSMakeRect(294, 11, 158, 16) size:8 bold:NO];
    self.localRTPDetailLabel.textColor = [NSColor colorWithWhite:0.68 alpha:1.0];
    self.localRTPDetailLabel.hidden = !self.localReturnMode;
    [targetPanel addSubview:self.localRTPDetailLabel];

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

    NSView *technicalPanel = self.technicalPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 47, 468, 132)];
    technicalPanel.wantsLayer = YES;
    technicalPanel.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.027 blue:0.038 alpha:1.0].CGColor;
    technicalPanel.layer.cornerRadius = 9.0;
    technicalPanel.layer.borderWidth = 0.5;
    technicalPanel.layer.borderColor = [NSColor colorWithWhite:0.28 alpha:0.65].CGColor;
    [content addSubview:technicalPanel];

    NSTextField *technicalTitle = [self label:@"INFORMATIONS TECHNIQUES" frame:NSMakeRect(16, 108, 250, 18) size:9 bold:YES];
    technicalTitle.textColor = NSColor.secondaryLabelColor;
    [technicalPanel addSubview:technicalTitle];
    NSTextField *technicalSubtitle = [self label:@"Auto · 2 s" frame:NSMakeRect(352, 109, 100, 16) size:7 bold:NO];
    technicalSubtitle.alignment = NSTextAlignmentRight;
    [technicalPanel addSubview:technicalSubtitle];

    [technicalPanel addSubview:[self label:@"SESSION RTP" frame:NSMakeRect(16, 82, 160, 16) size:8 bold:YES]];
    self.technicalSession = [self label:@"Analyse…" frame:NSMakeRect(16, 58, 208, 22) size:9 bold:NO];
    self.technicalSession.maximumNumberOfLines = 2;
    [technicalPanel addSubview:self.technicalSession];


    [technicalPanel addSubview:[self label:@"PORTS COREMIDI" frame:NSMakeRect(236, 82, 150, 16) size:8 bold:YES]];
    self.technicalEndpoints = [self label:@"Analyse…" frame:NSMakeRect(236, 58, 216, 22) size:9 bold:NO];
    self.technicalEndpoints.maximumNumberOfLines = 2;
    [technicalPanel addSubview:self.technicalEndpoints];

    [technicalPanel addSubview:[self label:@"PORT SÉLECTIONNÉ" frame:NSMakeRect(16, 36, 150, 16) size:8 bold:YES]];
    self.technicalSelection = [self label:@"Aucun" frame:NSMakeRect(16, 12, 208, 22) size:9 bold:NO];
    self.technicalSelection.maximumNumberOfLines = 2;
    [technicalPanel addSubview:self.technicalSelection];

    [technicalPanel addSubview:[self label:@"CORRESPONDANTS BONJOUR" frame:NSMakeRect(236, 36, 190, 16) size:8 bold:YES]];
    self.technicalPeers = [self label:@"Recherche…" frame:NSMakeRect(236, 12, 216, 22) size:9 bold:NO];
    self.technicalPeers.maximumNumberOfLines = 2;
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

    self.assistantReturnPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 151, 468, 154)];
    [content addSubview:self.assistantReturnPanel];
    self.assistantDevicesTitleLabel = [self label:@"APPAREILS SUIVIS" frame:NSMakeRect(20, 132, 250, 22) size:13 bold:YES];
    self.assistantDevicesTitleLabel.textColor = [NSColor colorWithRed:0.42 green:0.80 blue:0.88 alpha:1.0];
    [content addSubview:self.assistantDevicesTitleLabel];
    NSString *monitorProfileError = nil;
    self.deviceProfiles = [self loadDeviceProfilesForEditor:&monitorProfileError];
    self.expectedDeviceStates = [NSMutableDictionary dictionary];
    self.returnedDeviceStates = [NSMutableDictionary dictionary];
    [self rebuildReturnDeviceRouting];
    [self rebuildAssistantDeviceMonitoringCards];

    self.consoleLibrariesPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 225, 468, 116)];
    self.consoleLibrariesPanel.wantsLayer = YES;
    self.consoleLibrariesPanel.layer.cornerRadius = 12;
    self.consoleLibrariesPanel.layer.borderWidth = 1;
    self.consoleLibrariesPanel.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.065 blue:0.085 alpha:1.0].CGColor;
    self.consoleLibrariesPanel.layer.borderColor = [NSColor colorWithRed:0.44 green:0.62 blue:0.82 alpha:0.72].CGColor;
    [content addSubview:self.consoleLibrariesPanel];

    NSTextField *librariesTitle = [self label:@"BACKEND ET BIBLIOTHÈQUES" frame:NSMakeRect(14, 86, 250, 16) size:10 bold:YES];
    librariesTitle.textColor = [NSColor colorWithRed:0.48 green:0.76 blue:1.0 alpha:1.0];
    [self.consoleLibrariesPanel addSubview:librariesTitle];

    self.consoleLibrariesMode = [self label:@"● BACKEND · vérification…" frame:NSMakeRect(250, 86, 204, 16) size:8 bold:YES];
    self.consoleLibrariesMode.alignment = NSTextAlignmentRight;
    [self.consoleLibrariesPanel addSubview:self.consoleLibrariesMode];

    self.consoleLibraryNameLabels = [NSMutableDictionary dictionary];
    self.consoleLibraryStateLabels = [NSMutableDictionary dictionary];

    self.consoleLibrariesScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 5, 444, 76)];
    self.consoleLibrariesScroll.drawsBackground = NO;
    self.consoleLibrariesScroll.borderType = NSNoBorder;
    self.consoleLibrariesScroll.hasHorizontalScroller = NO;
    self.consoleLibrariesScroll.autohidesScrollers = YES;
    [self.consoleLibrariesPanel addSubview:self.consoleLibrariesScroll];

    [self rebuildConsoleLibraryRows];

    self.programChangeReturnsPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 231, 468, 68)];
    self.programChangeReturnsPanel.wantsLayer = YES;
    self.programChangeReturnsPanel.layer.cornerRadius = 10.0;
    self.programChangeReturnsPanel.layer.borderWidth = 1.0;
    self.programChangeReturnsPanel.layer.backgroundColor = [NSColor colorWithRed:0.040 green:0.052 blue:0.066 alpha:1.0].CGColor;
    self.programChangeReturnsPanel.layer.borderColor = [NSColor colorWithRed:0.24 green:0.55 blue:0.66 alpha:0.72].CGColor;
    [content addSubview:self.programChangeReturnsPanel];
    [self rebuildProgramChangeReturnCards];

    self.settingsButton = [self accentButton:@"Réseau MIDI…" frame:NSMakeRect(16, 53, 146, 32) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.62 alpha:1.0]]; [content addSubview:self.settingsButton];
    self.assistantDevicesButton = [self accentButton:@"⚙  Appareils…" frame:NSMakeRect(246, 701, 106, 30) action:@selector(openDevicesEditor:) color:[NSColor colorWithRed:0.18 green:0.38 blue:0.43 alpha:1.0]];
    self.assistantDevicesButton.toolTip = @"Configurer les appareils suivis";
    self.refreshButton = [self accentButton:@"Actualiser" frame:NSMakeRect(338, 53, 146, 32) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.10 green:0.46 blue:0.62 alpha:1.0]]; [content addSubview:self.refreshButton];
    [self loadSimulatorDevices];
    self.simulatorWindowButton = [self accentButton:@"Simulateur de retour…" frame:NSMakeRect(170, 53, 160, 32) action:@selector(openSimulatorWindow:) color:[NSColor colorWithRed:0.08 green:0.43 blue:0.39 alpha:1.0]];
    [content addSubview:self.simulatorWindowButton];
    self.assistantTestBanner = [[NSView alloc] initWithFrame:NSMakeRect(16, 42, 468, 36)];
    self.assistantTestBanner.wantsLayer = YES;
    self.assistantTestBanner.layer.cornerRadius = 9.0;
    self.assistantTestBanner.layer.backgroundColor = [NSColor colorWithRed:0.24 green:0.12 blue:0.035 alpha:1.0].CGColor;
    self.assistantTestBanner.layer.borderWidth = 1.0;
    self.assistantTestBanner.layer.borderColor = NSColor.systemOrangeColor.CGColor;
    self.assistantTestStatusLabel = [self label:@"Mode test actif" frame:NSMakeRect(12, 7, 300, 22) size:10 bold:YES];
    [self.assistantTestBanner addSubview:self.assistantTestStatusLabel];
    self.assistantStopTestsButton = [self accentButton:@"Tout arrêter" frame:NSMakeRect(354, 4, 100, 28) action:@selector(stopIntegratedSimulator:) color:[NSColor colorWithRed:0.62 green:0.20 blue:0.18 alpha:1.0]];
    self.assistantStopTestsButton.toolTip = @"Arrêter uniquement toutes les simulations actives";
    [self.assistantTestBanner addSubview:self.assistantStopTestsButton];
    [content addSubview:self.assistantTestBanner];
    NSTextField *footer = self.footerLabel = [self label:@"CL AUDIO · MIDI NETWORK · 2026" frame:NSMakeRect(16, 10, 468, 18) size:8 bold:YES];
    footer.alignment = NSTextAlignmentCenter; footer.textColor = [NSColor colorWithWhite:0.38 alpha:1.0]; [content addSubview:footer];
    self.compactSummary = [self label:@"Aucun test aller-retour validé" frame:NSMakeRect(24, 66, 452, 54) size:11 bold:YES];
    self.compactSummary.maximumNumberOfLines = 3; self.compactSummary.hidden = YES; [content addSubview:self.compactSummary];
    [content addSubview:self.assistantDevicesButton positioned:NSWindowAbove relativeTo:nil];

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

    self.simulatorAutoRestoreAttempts = 0;

    if (!self.backgroundMonitorOnly) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.5 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                [self restorePersistedSimulatorAutoDevices];
            }
        );
    }

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
    self.publishedLocalReturnAvailable = NO;
    if (![payload[@"service"] isEqualToString:@"cl-midi-console-monitor"]) return;
    NSTimeInterval publishedAt = [payload[@"updated_at"] doubleValue];
    BOOL publishedStateIsFresh = publishedAt > 0.0 &&
        MAX(0.0, NSDate.date.timeIntervalSince1970 - publishedAt) <= 6.0;
    self.publishedLocalReturnAvailable =
        publishedStateIsFresh &&
        [payload[@"online"] boolValue] &&
        [payload[@"return_mode"] isEqualToString:@"local_dedicated"] &&
        [payload[@"return_monitor_source"] isEqualToString:CLLocalReturnEndpointName] &&
        [payload[@"return_monitor_status"] integerValue] == noErr;
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

- (BOOL)localReturnIsAvailable {
    return self.localReturnDestination != 0 ||
        (!self.ownsPassiveReturnMonitor && self.publishedLocalReturnAvailable);
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
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSMutableArray<NSDictionary *> *visibleDevices = [NSMutableArray array];
    for (NSDictionary *device in self.deviceProfiles ?: @[]) {
        if (![device[@"enabled"] boolValue]) continue;
        NSDictionary *visibility = [device[@"visibility"] isKindOfClass:NSDictionary.class]
            ? device[@"visibility"] : @{};
        if (visibility[@"network_manager"] && ![visibility[@"network_manager"] boolValue]) continue;
        [visibleDevices addObject:device];
    }

    NSUInteger columns = visibleDevices.count == 1 ? 1 : 2;
    NSUInteger rows = visibleDevices.count == 3 ? 2 : MAX((NSUInteger)1, (visibleDevices.count + columns - 1) / columns);
    CGFloat cardHeight = visibleDevices.count <= 2 ? 106.0 : 100.0;
    CGFloat documentHeight = MAX(self.assistantReturnPanel.bounds.size.height,
                                 rows * (cardHeight + 7.0) + 3.0);
    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, documentHeight)];

    for (NSUInteger index = 0; index < visibleDevices.count; index++) {
        NSDictionary *profile = visibleDevices[index];
        NSString *deviceID = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        if (!deviceID.length) continue;

        BOOL fullWidthCard = columns == 1 || (visibleDevices.count == 3 && index == 2);
        NSUInteger row = (visibleDevices.count == 3 && index == 2) ? 1 : index / columns;
        NSUInteger column = index % columns;
        CGFloat cardWidth = fullWidthCard ? 442.0 : 216.0;
        CGFloat x = fullWidthCard ? 4.0 : (column == 0 ? 4.0 : 230.0);
        CGFloat y = documentHeight - ((row + 1) * (cardHeight + 7.0)) + 3.0;

        NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, y, cardWidth, cardHeight)];
        card.wantsLayer = YES;
        card.layer.cornerRadius = 8.0;
        card.layer.borderWidth = 1.0;
        card.layer.backgroundColor =
            [NSColor colorWithRed:0.045 green:0.055 blue:0.070 alpha:1.0].CGColor;

        NSInteger channel = [profile[@"midi_channel"] integerValue];
        CGFloat contentWidth = cardWidth - 20.0;
        NSTextField *name = [self label:profile[@"display_name"] ?: deviceID
                                  frame:NSMakeRect(10, cardHeight - 21, contentWidth - 62, 16)
                                   size:12 bold:YES];
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        NSTextField *channelLabel = [self label:[NSString stringWithFormat:@"CH %ld", (long)channel]
                                          frame:NSMakeRect(cardWidth - 62, cardHeight - 21, 52, 16)
                                           size:10 bold:YES];
        channelLabel.alignment = NSTextAlignmentRight;
        NSTextField *memory = [self label:@"—"
                                    frame:NSMakeRect(10, cardHeight - 56, contentWidth, 31)
                                     size:34 bold:YES];
        memory.alignment = NSTextAlignmentCenter;
        memory.font = [NSFont monospacedDigitSystemFontOfSize:28.0 weight:NSFontWeightHeavy];
        NSTextField *title = [self label:@""
                                   frame:NSMakeRect(10, cardHeight - 73, contentWidth, 17)
                                    size:13 bold:YES];
        title.alignment = NSTextAlignmentCenter;
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        NSTextField *state = [self label:@"Indéterminé"
                                   frame:NSMakeRect(10, 15, contentWidth, 14)
                                    size:9 bold:YES];
        state.alignment = NSTextAlignmentCenter;
        state.lineBreakMode = NSLineBreakByTruncatingTail;
        NSTextField *meta = [self label:@"Program Change brut —"
                                  frame:NSMakeRect(10, 3, contentWidth, 12)
                                   size:8 bold:NO];
        meta.alignment = NSTextAlignmentCenter;
        meta.textColor = [NSColor colorWithWhite:0.58 alpha:1.0];
        meta.lineBreakMode = NSLineBreakByTruncatingTail;

        [card addSubview:name]; [card addSubview:channelLabel]; [card addSubview:memory];
        [card addSubview:title]; [card addSubview:state]; [card addSubview:meta];
        [document addSubview:card];

        self.assistantDeviceViews[deviceID] = @{
            @"card": card,
            @"programLabel": memory,
            @"stateLabel": state,
            @"nameLabel": name,
            @"channelLabel": channelLabel,
            @"titleLabel": title,
            @"metaLabel": meta,
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
    [scroll.contentView scrollToPoint:NSMakePoint(
        0, MAX(0.0, documentHeight - scroll.contentView.bounds.size.height))];
    [scroll reflectScrolledClipView:scroll.contentView];
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

- (void)rebuildProgramChangeReturnCards {
    if (!self.programChangeReturnsPanel) return;
    for (NSView *view in self.programChangeReturnsPanel.subviews.copy) [view removeFromSuperview];
    self.programChangeReturnViews = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *profiles = [NSMutableArray array];
    for (NSDictionary *profile in self.deviceProfiles ?: @[]) {
        if (![profile[@"enabled"] boolValue]) continue;
        if (![[profile[@"protocol"] lowercaseString] isEqualToString:@"midi"]) continue;
        if (![[profile[@"signal_type"] lowercaseString] isEqualToString:@"program_change"]) continue;
        NSDictionary *visibility = [profile[@"visibility"] isKindOfClass:NSDictionary.class] ? profile[@"visibility"] : @{};
        if (visibility[@"network_manager"] && ![visibility[@"network_manager"] boolValue]) continue;
        [profiles addObject:profile];
    }
    NSTextField *title = [self label:@"RETOURS PROGRAM CHANGE" frame:NSMakeRect(12, self.programChangeReturnsPanel.bounds.size.height - 20, 300, 15) size:9 bold:YES];
    title.textColor = [NSColor colorWithRed:0.42 green:0.80 blue:0.88 alpha:1.0];
    [self.programChangeReturnsPanel addSubview:title];
    const CGFloat cardWidth = 140.0, cardHeight = 42.0, columnGap = 8.0, rowGap = 6.0;
    for (NSUInteger index = 0; index < profiles.count; index++) {
        NSDictionary *profile = profiles[index];
        NSString *deviceID = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        if (!deviceID.length) continue;
        NSUInteger row = index / 3, column = index % 3;
        CGFloat y = self.programChangeReturnsPanel.bounds.size.height - 24.0 - (row + 1) * cardHeight - row * rowGap;
        NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(12.0 + column * (cardWidth + columnGap), y, cardWidth, cardHeight)];
        card.wantsLayer = YES; card.layer.cornerRadius = 7.0; card.layer.borderWidth = 1.0;
        NSDictionary *palette = [profile[@"palette"] isKindOfClass:NSDictionary.class] ? profile[@"palette"] : @{};
        NSColor *accent = [self deviceColorFromHex:palette[@"accent"] fallback:[NSColor colorWithWhite:0.58 alpha:1.0]];
        card.layer.borderColor = accent.CGColor;
        card.layer.backgroundColor = [[NSColor colorWithRed:0.035 green:0.045 blue:0.058 alpha:1.0] blendedColorWithFraction:0.16 ofColor:accent].CGColor;
        NSTextField *name =
            [self label:profile[@"display_name"] ?: deviceID
                  frame:NSMakeRect(8, 23, 88, 15)
                   size:9
                   bold:YES];
        name.lineBreakMode = NSLineBreakByTruncatingTail;

        NSTextField *program =
            [self label:@"—"
                  frame:NSMakeRect(98, 21, 34, 18)
                   size:15
                   bold:YES];
        program.alignment = NSTextAlignmentRight;
        program.textColor = accent;

        NSTextField *returnTitle =
            [self label:@""
                  frame:NSMakeRect(8, 4, 88, 15)
                   size:8
                   bold:YES];
        returnTitle.lineBreakMode = NSLineBreakByTruncatingTail;

        NSTextField *state =
            [self label:@"—"
                  frame:NSMakeRect(96, 4, 36, 15)
                   size:7
                   bold:NO];
        state.alignment = NSTextAlignmentRight;
        state.textColor = NSColor.secondaryLabelColor;
        state.lineBreakMode = NSLineBreakByTruncatingTail;

        [card addSubview:name];
        [card addSubview:program];
        [card addSubview:returnTitle];
        [card addSubview:state];
        [self.programChangeReturnsPanel addSubview:card];

        self.programChangeReturnViews[deviceID] = @{
            @"card": card,
            @"programLabel": program,
            @"titleLabel": returnTitle,
            @"stateLabel": state
        };
    }
}

- (void)refreshProfileDrivenViews {
    // deviceProfiles reste l'unique source de vérité. Chaque collection UI
    // dynamique est reconstruite afin que les vues et leurs caches perdent
    // immédiatement toute référence à un profil supprimé ou devenu inéligible.
    [self rebuildAssistantDeviceMonitoringCards];
    [self rebuildProgramChangeReturnCards];
    [self updateConsoleReturnCards];
    [self syncSimulatorDevicesFromProfiles];
    [self rebuildSimulatorDeviceRows];
    [self rebuildConsoleLibraryRows];
    [self applyPresentationMode];
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
            : nil;
        if (!expected) {
            NSMutableDictionary *dynamicState = [NSMutableDictionary dictionary];
            NSDictionary *dynamicExpected = self.expectedDeviceStates[deviceID];
            NSDictionary *dynamicReturned = self.returnedDeviceStates[deviceID];
            if ([dynamicExpected isKindOfClass:NSDictionary.class]) [dynamicState addEntriesFromDictionary:dynamicExpected];
            if ([dynamicReturned isKindOfClass:NSDictionary.class]) [dynamicState addEntriesFromDictionary:dynamicReturned];
            if (!dynamicState[@"validation_status"]) dynamicState[@"validation_status"] = @"unavailable";
            expected = dynamicState;
        }

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
        NSDictionary *compactView = self.programChangeReturnViews[deviceID];
        if (compactView[@"card"]) {
            [cards addObject:compactView[@"card"]];
            [programLabels addObject:compactView[@"programLabel"]];
            [stateLabels addObject:compactView[@"stateLabel"]];
        }

        [consoles addObject:@{
            @"id": deviceID,
            @"name": name.length ? name : deviceID,
            @"expected": expected,
            @"cards": cards,
            @"programLabels": programLabels,
            @"stateLabels": stateLabels,
            @"palette": [profile[@"palette"] isKindOfClass:NSDictionary.class] ? profile[@"palette"] : @{},
            @"channel": [profile[@"midi_channel"] isKindOfClass:NSNumber.class] ? profile[@"midi_channel"] : @0,
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
        if (!ageValue && [expected[@"returned_received_at"] isKindOfClass:NSNumber.class]) {
            ageValue = @(MAX(0.0, NSDate.date.timeIntervalSince1970 -
                             [expected[@"returned_received_at"] doubleValue]));
        }
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
        NSColor *consoleConfirmedBackground = [consoleBackground blendedColorWithFraction:0.22 ofColor:consoleAccent];
        NSColor *consoleWaitingBackground = [consoleBackground blendedColorWithFraction:0.24 ofColor:consoleAccent];
        NSColor *consoleStaleBackground = [consoleBackground blendedColorWithFraction:0.32
                                                                           ofColor:[NSColor colorWithRed:0.025 green:0.030 blue:0.040 alpha:1.0]];
        NSString *runtimeState = confirmed
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
        for (NSUInteger index = 0; index < cards.count; index++) {
            if (cards[index] == NSNull.null) continue;
            NSView *card = cards[index]; NSTextField *programLabel = programLabels[index]; NSTextField *stateLabel = stateLabels[index];
            if (card == self.programChangeReturnViews[console[@"id"]][@"card"]) {
                NSDictionary *compactView =
                    self.programChangeReturnViews[console[@"id"]];
                NSTextField *compactTitleLabel =
                    compactView[@"titleLabel"];

                programLabel.stringValue = hasReturn
                    ? [NSString stringWithFormat:@"%ld", (long)receivedScene]
                    : @"—";

                NSString *compactReturnTitle =
                    hasReturn && returnedTitle.length
                    ? returnedTitle
                    : @"Titre non résolu";

                NSString *compactReturnState = !hasReturn
                    ? @"—"
                    : mismatch
                    ? @"✕ mismatch"
                    : stale
                    ? @"! ancien"
                    : @"✓ frais";

                compactTitleLabel.stringValue =
                    hasReturn ? compactReturnTitle : @"Aucun retour";

                compactTitleLabel.textColor = hasReturn
                    ? NSColor.labelColor
                    : NSColor.secondaryLabelColor;

                stateLabel.stringValue = compactReturnState;

                stateLabel.toolTip = hasReturn
                    ? [NSString stringWithFormat:@"%@ · %@",
                       compactReturnTitle,
                       runtimeState]
                    : @"Aucun retour";

                continue;
            }
            NSString *expectedDisplay = hasExpectedProgram ? [NSString stringWithFormat:@"%ld", (long)expectedProgram] : @"—";
            NSString *returnedDisplay = hasReturn ? [NSString stringWithFormat:@"%ld", (long)receivedScene] : @"—";
            NSString *validationMark = confirmed ? @"✓" : mismatch ? @"✕" : stale ? @"!" : @"…";
            programLabel.stringValue = [NSString stringWithFormat:@"%@   PC %@ → %@   %@", console[@"name"], expectedDisplay, returnedDisplay, validationMark];
            NSString *identity = [NSString stringWithFormat:@"%@ · canal %@",
                [console[@"productionSupported"] boolValue] ? @"Natif" : @"Configurable",
                console[@"channel"]];
            stateLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", identity, runtimeState];
            NSNumber *titleOffset = [expected[@"title_offset"] isKindOfClass:NSNumber.class] ? expected[@"title_offset"] : @0;
            id expectedLookup = expected[@"expected_title_lookup_memory"] ?: NSNull.null;
            id returnedLookup = expected[@"returned_title_lookup_memory"] ?: NSNull.null;
            (void)expectedTitle; (void)returnedTitle; (void)titleOffset; (void)expectedLookup; (void)returnedLookup;
            (void)expectedSource; (void)returnedSource; (void)expectedProgramSource; (void)returnedProgramSource; (void)latencyValue;
            card.layer.backgroundColor = (confirmed
                ? consoleConfirmedBackground
                : stale
                ? consoleStaleBackground
                : consoleBackground).CGColor;
            card.layer.borderColor = consoleAccent.CGColor;
            card.layer.borderWidth = mismatch ? 3.0 : (confirmed ? 2.0 : 1.5);
            card.layer.shadowColor = consoleAccent.CGColor;
            card.layer.shadowOffset = CGSizeZero;
            card.layer.shadowOpacity = mismatch ? 0.52 : (confirmed ? 0.30 : (stale ? 0.05 : 0.16));
            card.layer.shadowRadius = mismatch ? 12.0 : (confirmed ? 8.0 : (stale ? 2.0 : 5.0));

            NSString *visualState = confirmed
                ? @"confirmed"
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
            } else if (([visualState isEqualToString:@"waiting"] ||
                        [visualState isEqualToString:@"recall_waiting"]) &&
                       [card.layer animationForKey:@"clConsolePulse"] == nil) {
                CABasicAnimation *haloPulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                haloPulse.fromValue = @0.08;
                haloPulse.toValue = @0.34;
                CABasicAnimation *backgroundPulse = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
                backgroundPulse.fromValue = (__bridge id)consoleBackground.CGColor;
                backgroundPulse.toValue = (__bridge id)consoleWaitingBackground.CGColor;
                CAAnimationGroup *pulse = [CAAnimationGroup animation];
                pulse.animations = @[haloPulse, backgroundPulse];
                pulse.duration = 1.60;
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
                    (__bridge id)consoleConfirmedBackground.CGColor
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

        NSDictionary *assistantView = self.assistantDeviceViews[console[@"id"]];
        if (assistantView) {
            NSDictionary *profile = assistantView[@"profile"];
            NSString *signalType = [profile[@"signal_type"] lowercaseString] ?: @"program_change";
            BOOL isProgramChange = [signalType isEqualToString:@"program_change"];
            BOOL isControlChange = [signalType isEqualToString:@"control_change"];
            BOOL isNote = [signalType isEqualToString:@"note"];
            BOOL hasLibrary = [profile[@"library"] isKindOfClass:NSString.class];
            BOOL showReturned = isProgramChange && hasReturn;
            NSInteger dominantMemory = isProgramChange ? (showReturned ? receivedScene : expectedProgram) : 0;
            NSInteger rawProgram = dominantMemory > 0 ? dominantMemory - 1 : -1;
            NSTextField *memoryLabel = assistantView[@"programLabel"];
            NSTextField *titleLabel = assistantView[@"titleLabel"];
            NSTextField *statusLabel = assistantView[@"stateLabel"];
            NSTextField *metaLabel = assistantView[@"metaLabel"];
            NSTextField *nameLabel = assistantView[@"nameLabel"];
            NSTextField *channelLabel = assistantView[@"channelLabel"];
            memoryLabel.stringValue = dominantMemory > 0
                ? [NSString stringWithFormat:@"%ld", (long)dominantMemory] : @"—";
            NSString *resolvedTitle = showReturned ? returnedTitle : expectedTitle;
            titleLabel.stringValue = hasLibrary && resolvedTitle.length
                ? resolvedTitle : @"";
            titleLabel.hidden = !titleLabel.stringValue.length;
            NSString *waitingLabel = isControlChange
                ? @"En attente d’un Control Change"
                : isNote
                ? @"En attente d’une Note"
                : @"En attente d’un Program Change";

            statusLabel.stringValue = isProgramChange && [console[@"productionSupported"] boolValue]
                ? runtimeState
                : isProgramChange && hasReturn
                ? [NSString stringWithFormat:@"RETURNED · %@",
                    ageValue ? CLMidiAgeDescription(ageValue.doubleValue) : @"retour reçu"]
                : isProgramChange && hasExpectedProgram
                ? @"EXPECTED · en attente"
                : waitingLabel;
            if (isProgramChange) {
                NSString *expectedMeta = hasExpectedProgram
                    ? [NSString stringWithFormat:@" · EXP %ld", (long)expectedProgram] : @"";
                NSString *compactAge = ageValue
                    ? [CLMidiAgeDescription(ageValue.doubleValue) stringByReplacingOccurrencesOfString:@"il y a " withString:@""]
                    : @"";
                NSString *ageMeta = compactAge.length ? [NSString stringWithFormat:@" · %@", compactAge] : @"";
                metaLabel.stringValue = rawProgram >= 0
                    ? [NSString stringWithFormat:@"Program Change %ld%@%@",
                        (long)rawProgram, expectedMeta, ageMeta]
                    : @"Program Change";
            } else if (isControlChange) {
                metaLabel.stringValue = @"Control Change";
            } else if (isNote) {
                metaLabel.stringValue = @"Note";
            } else {
                metaLabel.stringValue = @"MIDI";
            }
            nameLabel.textColor = identityBase;
            channelLabel.textColor = [identityBase colorWithAlphaComponent:0.82];
            memoryLabel.textColor = identityBase;
            titleLabel.textColor = NSColor.labelColor;
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
        // Même source canonique que la télécommande Ableton :
        // device_states est la vue métier déjà résolue par le backend
        // (EXPECTED / RETURNED / titres / validation / fraîcheur).
        // midi_console reste uniquement un fallback de compatibilité.
        NSDictionary *deviceStates = [payload[@"device_states"] isKindOfClass:NSDictionary.class]
            ? payload[@"device_states"] : @{};
        NSDictionary *midiConsole = [payload[@"midi_console"] isKindOfClass:NSDictionary.class]
            ? payload[@"midi_console"] : @{};

        NSDictionary *consoleA = [deviceStates[@"console_a"] isKindOfClass:NSDictionary.class]
            ? deviceStates[@"console_a"] : nil;
        NSDictionary *consoleB = [deviceStates[@"console_b"] isKindOfClass:NSDictionary.class]
            ? deviceStates[@"console_b"] : nil;

        NSDictionary *cl5 = consoleA ?: (
            [midiConsole[@"cl5"] isKindOfClass:NSDictionary.class]
                ? midiConsole[@"cl5"] : @{}
        );
        NSDictionary *ql1 = consoleB ?: (
            [midiConsole[@"ql1"] isKindOfClass:NSDictionary.class]
                ? midiConsole[@"ql1"] : @{}
        );
        dispatch_async(dispatch_get_main_queue(), ^{
            if (title.length && ![title isEqualToString:@"—"]) self.currentAbletonSceneTitle = title;
            self.expectedCL5State = cl5;
            self.expectedQL1State = ql1;
            [self updateConsoleLibrariesFromStatus:payload];
            [self updateConsoleReturnCards];
        });
    }] resume];
}

- (void)rebuildConsoleLibraryRows {
    if (!self.consoleLibrariesScroll) return;

    [self.consoleLibraryNameLabels removeAllObjects];
    [self.consoleLibraryStateLabels removeAllObjects];

    NSMutableArray<NSDictionary *> *definitions = [NSMutableArray array];
    NSMutableSet<NSString *> *seenLibraries = [NSMutableSet set];

    for (NSDictionary *device in self.deviceProfiles) {
        NSString *protocol = [device[@"protocol"] isKindOfClass:NSString.class]
            ? [device[@"protocol"] lowercaseString] : @"";
        NSString *signalType = [device[@"signal_type"] isKindOfClass:NSString.class]
            ? [device[@"signal_type"] lowercaseString] : @"";
        id rawLibrary = device[@"library"];
        NSString *libraryID = [rawLibrary isKindOfClass:NSString.class]
            ? [rawLibrary lowercaseString] : @"";

        if (![protocol isEqualToString:@"midi"] ||
            ![signalType isEqualToString:@"program_change"] ||
            !libraryID.length ||
            [seenLibraries containsObject:libraryID]) {
            continue;
        }

        [seenLibraries addObject:libraryID];
        [definitions addObject:@{
            @"id": libraryID,
            @"name": [device[@"display_name"] isKindOfClass:NSString.class]
                ? device[@"display_name"] : libraryID.uppercaseString,
            @"channel": [NSString stringWithFormat:@"Ch.%ld",
                (long)[device[@"midi_channel"] integerValue]],
            @"palette": [device[@"palette"] isKindOfClass:NSDictionary.class]
                ? device[@"palette"] : @{}
        }];
    }

    CGFloat rowHeight = 24.0;
    CGFloat rowStep = 26.0;
    CGFloat visibleHeight = 76.0;
    CGFloat documentHeight = MAX(visibleHeight, definitions.count * rowStep);

    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 444, documentHeight)];

    if (!definitions.count) {
        NSTextField *empty = [self label:@"Aucune bibliothèque associée à un appareil Program Change"
                                   frame:NSMakeRect(8, 16, 420, 18)
                                    size:9
                                    bold:NO];
        empty.textColor = NSColor.secondaryLabelColor;
        [document addSubview:empty];
    }

    for (NSUInteger index = 0; index < definitions.count; index++) {
        NSDictionary *definition = definitions[index];
        NSDictionary *palette = definition[@"palette"];
        NSColor *accent = [self deviceColorFromHex:palette[@"accent"]
                                         fallback:NSColor.systemBlueColor];

        CGFloat y = documentHeight - rowHeight - (index * rowStep);

        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, y, 444, rowHeight)];
        row.wantsLayer = YES;
        row.layer.cornerRadius = 5;
        row.layer.backgroundColor = [NSColor colorWithWhite:0.12 alpha:0.46].CGColor;

        NSView *stripe = [[NSView alloc] initWithFrame:NSMakeRect(0, 3, 3, 18)];
        stripe.wantsLayer = YES;
        stripe.layer.cornerRadius = 1.5;
        stripe.layer.backgroundColor = accent.CGColor;
        [row addSubview:stripe];

        NSTextField *deviceName = [self label:definition[@"name"]
                                        frame:NSMakeRect(10, 3, 62, 17)
                                         size:10
                                         bold:YES];
        deviceName.textColor = accent;
        deviceName.lineBreakMode = NSLineBreakByTruncatingTail;
        [row addSubview:deviceName];

        NSTextField *channel = [self label:definition[@"channel"]
                                     frame:NSMakeRect(76, 3, 38, 17)
                                      size:8
                                      bold:NO];
        channel.textColor = NSColor.secondaryLabelColor;
        [row addSubview:channel];

        NSTextField *libraryName = [self label:@"—"
                                         frame:NSMakeRect(118, 3, 104, 17)
                                          size:9
                                          bold:YES];
        libraryName.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [row addSubview:libraryName];

        NSTextField *libraryState = [self label:@"Bibliothèque non configurée"
                                          frame:NSMakeRect(226, 3, 148, 17)
                                           size:8
                                           bold:NO];
        libraryState.textColor = NSColor.secondaryLabelColor;
        libraryState.lineBreakMode = NSLineBreakByTruncatingTail;
        [row addSubview:libraryState];

        NSButton *modify = [self accentButton:@"Modifier"
                                        frame:NSMakeRect(382, 1, 58, 21)
                                       action:@selector(selectConsoleLibrary:)
                                        color:[accent colorWithAlphaComponent:0.72]];
        modify.identifier = definition[@"id"];
        modify.toolTip = [NSString stringWithFormat:@"Modifier la bibliothèque %@",
                          definition[@"name"]];
        [row addSubview:modify];

        document.autoresizesSubviews = YES;
        [document addSubview:row];

        self.consoleLibraryNameLabels[definition[@"id"]] = libraryName;
        self.consoleLibraryStateLabels[definition[@"id"]] = libraryState;
    }

    self.consoleLibrariesScroll.hasVerticalScroller = definitions.count > 3;
    self.consoleLibrariesScroll.documentView = document;

    if (documentHeight > visibleHeight) {
        [self.consoleLibrariesScroll.contentView
            scrollToPoint:NSMakePoint(0, documentHeight - visibleHeight)];
        [self.consoleLibrariesScroll reflectScrolledClipView:self.consoleLibrariesScroll.contentView];
    }
}

- (void)updateConsoleLibrariesFromStatus:(NSDictionary *)status {
    NSDictionary *libraries = [status[@"console_scene_library_status"] isKindOfClass:NSDictionary.class]
        ? status[@"console_scene_library_status"] : @{};
    NSString *mode = [status[@"console_title_mode"] isKindOfClass:NSString.class]
        ? status[@"console_title_mode"] : @"";

    BOOL importedLibraryMode = [mode isEqualToString:@"imported_library"];
    NSUInteger libraryCount = self.consoleLibraryNameLabels.count;
    NSUInteger validLibraryCount = 0;

    for (NSString *libraryID in self.consoleLibraryNameLabels) {
        NSDictionary *healthInfo = [libraries[libraryID] isKindOfClass:NSDictionary.class]
            ? libraries[libraryID] : @{};
        NSString *healthStatus = [healthInfo[@"status"] isKindOfClass:NSString.class]
            ? healthInfo[@"status"] : @"Backend indisponible";
        NSArray *healthEntries = [healthInfo[@"entries"] isKindOfClass:NSArray.class]
            ? healthInfo[@"entries"] : @[];

        if ([healthStatus isEqualToString:@"Valide"] && healthEntries.count > 0) {
            validLibraryCount += 1;
        }
    }

    BOOL librariesHealthy =
        importedLibraryMode &&
        libraryCount > 0 &&
        validLibraryCount == libraryCount;

    if (librariesHealthy) {
        self.consoleLibrariesMode.stringValue =
            [NSString stringWithFormat:@"● BACKEND ACTIF · %lu/%lu",
             (unsigned long)validLibraryCount,
             (unsigned long)libraryCount];
        self.consoleLibrariesMode.textColor =
            [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0];

        self.backendCompactStatus.stringValue =
            [NSString stringWithFormat:@"● BACKEND %lu/%lu",
             (unsigned long)validLibraryCount,
             (unsigned long)libraryCount];
        self.backendCompactStatus.textColor =
            [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0];

    } else if (importedLibraryMode) {
        self.consoleLibrariesMode.stringValue =
            [NSString stringWithFormat:@"⚠ BACKEND PARTIEL · %lu/%lu",
             (unsigned long)validLibraryCount,
             (unsigned long)libraryCount];
        self.consoleLibrariesMode.textColor = NSColor.systemOrangeColor;

        self.backendCompactStatus.stringValue =
            [NSString stringWithFormat:@"⚠ BACKEND %lu/%lu",
             (unsigned long)validLibraryCount,
             (unsigned long)libraryCount];
        self.backendCompactStatus.textColor = NSColor.systemOrangeColor;

    } else {
        self.consoleLibrariesMode.stringValue =
            @"● BACKEND INACTIF · titres Ableton";
        self.consoleLibrariesMode.textColor = NSColor.systemRedColor;

        self.backendCompactStatus.stringValue = @"● BACKEND OFF";
        self.backendCompactStatus.textColor = NSColor.systemRedColor;
    }

    for (NSString *libraryID in self.consoleLibraryNameLabels) {
        NSDictionary *info = [libraries[libraryID] isKindOfClass:NSDictionary.class]
            ? libraries[libraryID] : @{};
        NSString *statusText = [info[@"status"] isKindOfClass:NSString.class]
            ? info[@"status"] : @"Backend indisponible";
        NSString *sourceName = [info[@"source_name"] isKindOfClass:NSString.class]
            ? info[@"source_name"] : @"";
        if (!sourceName.length && [info[@"path"] isKindOfClass:NSString.class])
            sourceName = [info[@"path"] lastPathComponent];

        NSArray *entries = [info[@"entries"] isKindOfClass:NSArray.class]
            ? info[@"entries"] : @[];
        BOOL valid = [statusText isEqualToString:@"Valide"] && entries.count > 0;

        NSTextField *nameLabel = self.consoleLibraryNameLabels[libraryID];
        NSTextField *stateLabel = self.consoleLibraryStateLabels[libraryID];
        nameLabel.stringValue = sourceName.length ? sourceName : @"Aucune bibliothèque";
        stateLabel.stringValue = valid
            ? [NSString stringWithFormat:@"✓ %lu mémoires", (unsigned long)entries.count]
            : [NSString stringWithFormat:@"⚠ %@", statusText];
        stateLabel.textColor = valid
            ? [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0]
            : NSColor.systemOrangeColor;
    }
}

- (void)selectConsoleLibrary:(NSButton *)sender {
    NSString *console = sender.identifier.lowercaseString;
    if (!console.length || !self.consoleLibraryNameLabels[console]) return;
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
            NSArray *entries = [reply[@"library"][@"entries"] isKindOfClass:NSArray.class]
                ? reply[@"library"][@"entries"] : @[];
            self.lastTest.stringValue = ok
                ? [NSString stringWithFormat:@"%@ · %lu mémoire%@ reconnue%@",
                    reply[@"message"] ?: @"Bibliothèque importée", (unsigned long)entries.count,
                    entries.count > 1 ? @"s" : @"", entries.count > 1 ? @"s" : @""]
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

    // Le mode Local conserve son endpoint RETURNED dédié, mais le retour
    // physique RTP reste observé passivement en parallèle.
    NSString *preferredReturnSource =
        CLPreferredConsoleReturnEndpoint(EndpointNames(YES));
    if (preferredReturnSource.length) {
        [self selectPassiveReturnSourceNamed:preferredReturnSource];
    }

    // Le retour de production reste le vrai source monitorée,
    // y compris quand Ableton fonctionne en local.
    // CL MIDI Return Test reste uniquement disponible pour le simulateur/test.
    if (!preferredReturnSource.length && self.localReturnMode) {
        self.returnMonitorStatus =
            self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;
    }

    [self writeConsoleReturnState];
    [self updateRoundTripPanelForCurrentMode];
}

- (void)recordIsolatedDeviceTestProgram:(UInt8)program channel:(UInt8)channel source:(NSString *)source {
    [self recordIsolatedDeviceTestMessageType:@"program_change"
                                      channel:channel
                                        data1:program
                                        data2:-1
                                       source:source];
}

- (void)recordIsolatedDeviceTestMessageType:(NSString *)type
                                    channel:(UInt8)channel
                                      data1:(UInt8)data1
                                      data2:(NSInteger)data2
                                     source:(NSString *)source {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;

    self.deviceTestReceived = @{
        @"type": type ?: @"",
        @"channel": @(channel),
        @"data1": @(data1),
        @"data2": @(data2),
        @"timestamp": @(now),
        @"source": source ?: @""
    };

    NSString *sentType = self.deviceTestSent[@"type"];
    NSNumber *sentChannel = self.deviceTestSent[@"channel"];
    NSNumber *sentData1 = self.deviceTestSent[@"data1"];
    NSNumber *sentData2 = self.deviceTestSent[@"data2"];

    BOOL match =
        sentType &&
        [sentType isEqualToString:type] &&
        sentChannel.unsignedCharValue == channel &&
        sentData1.unsignedCharValue == data1 &&
        sentData2.integerValue == data2;

    NSTimeInterval latency = self.deviceTestSent
        ? (now - [self.deviceTestSent[@"timestamp"] doubleValue]) * 1000.0
        : 0;

    if (self.deviceRoundTripPending) {
        if (match &&
            [source isEqualToString:self.deviceTestSourceMenu.titleOfSelectedItem] &&
            latency >= 0.0) {
            self.deviceRoundTripPending = NO;
            self.deviceRoundTripGeneration++;

            NSString *detail = nil;
            if ([type isEqualToString:@"program_change"])
                detail = [NSString stringWithFormat:@"Program Change · mémoire %u", data1 + 1];
            else if ([type isEqualToString:@"control_change"])
                detail = [NSString stringWithFormat:@"CC %u · valeur %ld", data1, (long)data2];
            else
                detail = [NSString stringWithFormat:@"%@ · note %u · vélocité %ld",
                          [type isEqualToString:@"note_off"] ? @"Note Off" : @"Note On",
                          data1, (long)data2];

            self.deviceTestResult.stringValue =
                [NSString stringWithFormat:@"ROUND TRIP TEST PASS · %@ · Ch.%u · %@ · %.1f ms",
                 source, channel, detail, latency];
        }
        return;
    }

    NSString *detail = nil;
    if ([type isEqualToString:@"program_change"])
        detail = [NSString stringWithFormat:@"Program Change · raw %u · mémoire %u", data1, data1 + 1];
    else if ([type isEqualToString:@"control_change"])
        detail = [NSString stringWithFormat:@"CC · %u · valeur %ld", data1, (long)data2];
    else
        detail = [NSString stringWithFormat:@"%@ · note %u · vélocité %ld",
                  [type isEqualToString:@"note_off"] ? @"Note Off" : @"Note On",
                  data1, (long)data2];

    NSString *state = self.deviceTestSent ? (match ? @"MATCH" : @"MISMATCH") : @"OBSERVÉ";

    self.deviceTestResult.stringValue =
        [NSString stringWithFormat:@"TEST RX · %@ · Ch.%u · %@ · %@%@",
         source, channel, detail, state,
         self.deviceTestSent ? [NSString stringWithFormat:@" · %.1f ms", latency] : @""];
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
    self.expectedMonitorSourceName = nil;
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
        self.expectedMonitorSourceName = name;
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
    self.returnMonitorSourceName = nil;
    if (selectedSource && self.returnMonitorInputPort &&
        (self.returnMonitorStatus = MIDIPortConnectSource(
            self.returnMonitorInputPort, selectedSource, NULL
        )) == noErr) {
        self.returnMonitorSource = selectedSource;
        self.returnMonitorSourceName = name;
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
    self.assistantDevicesTitleLabel.hidden = detailed;
    self.assistantDevicesButton.hidden = NO;
    self.assistantDevicesButton.enabled = YES;
    self.assistantDevicesButton.target = self;
    self.assistantDevicesButton.action = @selector(openDevicesEditor:);
    self.consoleLibrariesPanel.hidden = !detailed;
    self.programChangeReturnsPanel.hidden = !detailed;
    self.simulatorWindowButton.hidden = !detailed;
    self.assistantTestBanner.hidden = detailed || self.simulatorTasks.count == 0;
    self.compactSummary.hidden = YES;
    self.showModeButton.title = detailed ? @"Vue Spectacle" : @"Diagnostic détaillé";
    self.remoteTargetTitleLabel.hidden = self.localReturnMode;
    self.targetMenu.hidden = self.localReturnMode;
    self.connectButton.hidden = self.localReturnMode;
    self.localRTPNoteLabel.hidden = !detailed || !self.localReturnMode;
    self.localRTPDetailLabel.hidden = !detailed || !self.localReturnMode;
    self.operatingModeReasonLabel.hidden = detailed;
    [self updateRoundTripPanelForCurrentMode];
    [self updateAssistantPrimaryStatus];
    if (detailed) {
        NSUInteger returnCount = self.programChangeReturnViews.count;
        NSUInteger returnRows = MAX((NSUInteger)1, (returnCount + 2) / 3);
        CGFloat returnsHeight = 32.0 + returnRows * 42.0 + (returnRows - 1) * 6.0;
        CGFloat localHeight = MIN(768.0, MAX(690.0, 650.0 + returnsHeight));
        CGFloat offset = self.localReturnMode ? 0.0 : 104.0;
        CGFloat actionsY = 190.0;
        [self.window setContentSize:NSMakeSize(500, localHeight + offset)];
        self.headerPanel.frame = NSMakeRect(16, localHeight - 80 + offset, 468, 64);
        self.appTitleLabel.frame = NSMakeRect(20, localHeight - 120 + offset, 220, 24);
        self.appSubtitleLabel.frame = NSMakeRect(0, 0, 1, 1);
        self.showModeButton.frame = NSMakeRect(360, localHeight - 123 + offset, 124, 30);
        self.assistantDevicesButton.frame = NSMakeRect(246, localHeight - 123 + offset, 106, 30);
        self.statusPanel.frame = NSMakeRect(16, localHeight - 192 + offset, 468, 62);

        CGFloat modePanelHeight = 58.0;
        self.targetPanel.frame = NSMakeRect(16, localHeight - 250 + offset, 468, modePanelHeight);
        self.generalModeTitleLabel.stringValue = self.localReturnMode ? @"MODE · LOCAL" : @"MODE GÉNÉRAL";
        self.generalModeTitleLabel.frame = self.localReturnMode
            ? NSMakeRect(14, 21, 96, 18) : NSMakeRect(12, 36, 96, 16);
        self.returnModeMenu.frame = self.localReturnMode
            ? NSMakeRect(116, 13, 164, 32) : NSMakeRect(12, 5, 148, 30);
        self.remoteTargetTitleLabel.frame = NSMakeRect(168, 36, 214, 16);
        self.targetMenu.frame = NSMakeRect(168, 5, 188, 30);
        self.connectButton.frame = NSMakeRect(364, 5, 92, 30);
        self.localRTPNoteLabel.frame = NSMakeRect(294, 29, 158, 16);
        self.localRTPDetailLabel.frame = NSMakeRect(294, 11, 158, 16);
        [self stylePopup:self.returnModeMenu accent:self.localReturnMode
            ? [NSColor colorWithRed:0.58 green:0.34 blue:0.19 alpha:1.0]
            : [NSColor colorWithRed:0.34 green:0.52 blue:0.68 alpha:1.0]];

        // En distant uniquement, le diagnostic RTP occupe l'espace
        // supplémentaire fourni par offset.
        self.testPanel.frame = NSMakeRect(16, actionsY + 59.0 + returnsHeight + 116.0, 468, 96);

        // Trois bibliothèques restent visibles.
        self.programChangeReturnsPanel.frame = NSMakeRect(16, actionsY + 41.0, 468, returnsHeight);
        [self rebuildProgramChangeReturnCards];
        [self updateConsoleReturnCards];
        self.consoleLibrariesPanel.frame = NSMakeRect(16, actionsY + 50.0 + returnsHeight, 468, 116);

        // Le simulateur étant désormais une palette séparée, son accès
        // n'a plus besoin de réserver un grand panneau vide.
        self.settingsButton.frame = NSMakeRect(16, actionsY, 146, 32);
        self.simulatorWindowButton.frame = NSMakeRect(170, actionsY, 160, 32);
        self.refreshButton.frame = NSMakeRect(338, actionsY, 146, 32);

        // Les informations techniques remontent immédiatement sous l'accès
        // au simulateur.
        self.technicalPanel.frame = NSMakeRect(16, 47, 468, 132);

        self.footerLabel.frame = NSMakeRect(16, 10, 468, 18);
    } else {
        [self layoutAssistantViewForRTPMode:!self.localReturnMode];
    }
}

- (void)layoutAssistantViewForRTPMode:(BOOL)rtpMode {
    CGFloat offset = rtpMode ? 104.0 : 0.0;
    NSSize targetContentSize = NSMakeSize(500, 650 + offset);
    NSSize currentContentSize = self.window.contentView.bounds.size;
    if (fabs(currentContentSize.width - targetContentSize.width) > 0.5 ||
        fabs(currentContentSize.height - targetContentSize.height) > 0.5) {
        [self.window setContentSize:targetContentSize];
    }
    self.headerPanel.frame = NSMakeRect(16, 570 + offset, 468, 64);
    self.appTitleLabel.frame = NSMakeRect(20, 530 + offset, 220, 24); self.appSubtitleLabel.frame = NSMakeRect(0, 0, 1, 1);
    self.showModeButton.frame = NSMakeRect(360, 527 + offset, 124, 30); self.statusPanel.frame = NSMakeRect(16, 458 + offset, 468, 62);
    CGFloat modePanelHeight = rtpMode ? 100.0 : 58.0;
    CGFloat modePanelY = rtpMode ? 350.0 + offset : 392.0;
    self.targetPanel.frame = NSMakeRect(16, modePanelY, 468, modePanelHeight); self.testPanel.frame = NSMakeRect(16, 343, 468, 96);
    self.generalModeTitleLabel.stringValue = rtpMode ? @"MODE GÉNÉRAL" : @"MODE · LOCAL";
    self.generalModeTitleLabel.frame = rtpMode ? NSMakeRect(16, 68, 150, 20) : NSMakeRect(16, 31, 140, 18);
    self.returnModeMenu.frame = rtpMode ? NSMakeRect(16, 28, 168, 34) : NSMakeRect(276, 12, 176, 34);
    self.remoteTargetTitleLabel.frame = NSMakeRect(194, 68, 210, 20);
    self.targetMenu.frame = NSMakeRect(194, 28, 166, 34);
    self.connectButton.frame = NSMakeRect(370, 27, 82, 36);
    self.operatingModeReasonLabel.frame = NSMakeRect(16, 6, 436, 18);
    self.assistantDevicesTitleLabel.frame = NSMakeRect(20, 313, 250, 22);
    self.assistantDevicesButton.frame = NSMakeRect(246, 527 + offset, 106, 30);
    self.assistantReturnPanel.frame = NSMakeRect(16, 90, 468, 215);
    self.assistantDevicesScroll.frame = self.assistantReturnPanel.bounds;
    self.assistantTestBanner.frame = NSMakeRect(16, 42, 468, 36);
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
    self.transportHeadline = title ?: @"";
    self.transportDetail = detail ?: @"";
    if (!self.showModeEnabled) { [self updateAssistantPrimaryStatus]; return; }
    self.lamp.layer.backgroundColor = color.CGColor;
    self.lamp.layer.shadowColor = color.CGColor;
    self.lamp.layer.shadowOpacity = 0.75;
    self.lamp.layer.shadowRadius = 8;
    self.headline.stringValue = title;
    self.detail.stringValue = detail;
}

- (void)updateAssistantPrimaryStatus {
    if (self.showModeEnabled) {
        self.headline.stringValue = self.transportHeadline.length ? self.transportHeadline : @"DIAGNOSTIC";
        self.detail.stringValue = self.transportDetail ?: @"";
        return;
    }
    NSString *mode = self.localReturnMode ? @"Ableton local" : @"Ableton distant";
    NSColor *color = NSColor.systemOrangeColor;
    NSString *verdict = @"ATTENTION REQUISE";
    NSString *explanation;
    if (!self.showControlAvailable) {
        explanation = [NSString stringWithFormat:@"%@ · Show Control indisponible, mode conservé localement.", mode];
    } else if (self.localReturnMode && [self localReturnIsAvailable]) {
        color = NSColor.systemGreenColor; verdict = @"PRÊT";
        explanation = @"Ableton local · retour MIDI local disponible · RTP non requis.";
    } else if (self.localReturnMode) {
        color = NSColor.systemRedColor; verdict = @"INDISPONIBLE";
        explanation = @"Ableton local · retour MIDI local indisponible · RTP non requis.";
    } else if ([self.lastRTPTestStatus isEqualToString:@"validated"]) {
        color = NSColor.systemGreenColor; verdict = @"PRÊT";
        explanation = @"Ableton distant · liaison RTP validée par un aller-retour MIDI.";
    } else if ([self.lastRTPTestStatus isEqualToString:@"running"]) {
        explanation = @"Ableton distant · test RTP en cours.";
    } else if ([self.lastRTPTestStatus isEqualToString:@"available"]) {
        explanation = @"Ableton distant · RTP disponible, mais non validé par un aller-retour.";
    } else if ([self.lastRTPTestStatus isEqualToString:@"loop_detected"]) {
        color = NSColor.systemRedColor; verdict = @"INDISPONIBLE";
        explanation = @"Ableton distant · boucle MIDI détectée sur la liaison RTP.";
    } else if ([self.lastRTPTestStatus isEqualToString:@"failed"] ||
               [self.lastRTPTestStatus isEqualToString:@"timeout"] ||
               [self.lastRTPTestStatus isEqualToString:@"send_error"]) {
        color = NSColor.systemRedColor; verdict = @"INDISPONIBLE";
        explanation = @"Ableton distant · le dernier test RTP a échoué.";
    } else {
        color = NSColor.systemRedColor; verdict = @"INDISPONIBLE";
        explanation = @"Ableton distant · aucune cible RTP distante n’est détectée.";
    }
    self.lamp.layer.backgroundColor = color.CGColor;
    self.lamp.layer.shadowColor = color.CGColor;
    self.lamp.layer.shadowOpacity = 0.65;
    self.lamp.layer.shadowRadius = 7.0;
    self.headline.stringValue = [NSString stringWithFormat:@"%@ · %@", verdict, mode];
    self.detail.stringValue = explanation;
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
        [self selectPassiveReturnSourceNamed:endpoint];
        [self writeConsoleReturnState];
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
    self.targetMenu.enabled = !local;
    self.connectButton.enabled = !local && self.discoveredPeers.count > 0 && !self.systemConnectRunning;
    self.connectButton.title = local ? @"Non requis" : @"Connecter";
    self.connectButton.toolTip = local
        ? @"Aucune connexion RTP n’est requise en mode Ableton local."
        : (self.discoveredPeers.count ? @"Demander à macOS de connecter la cible RTP sélectionnée."
                                     : @"Aucune cible RTP distante n’est actuellement détectée.");
    self.remoteTargetTitleLabel.hidden = local;
    self.targetMenu.hidden = local;
    self.connectButton.hidden = local;
    self.localRTPNoteLabel.hidden = !self.showModeEnabled || !local;
    self.localRTPDetailLabel.hidden = !self.showModeEnabled || !local;
    if (self.simulatorModeLabel) self.simulatorModeLabel.stringValue = local ? @"Ableton local · dérivé du mode général" : @"Ableton distant · dérivé du mode général";
    [NSUserDefaults.standardUserDefaults setObject:(local ? @"local_dedicated" : @"rtp_remote")
                                            forKey:@"consoleReturnMode"];
    if (!changed) {
        if (message.length) self.lastTest.stringValue = message;
        [self updateRoundTripPanelForCurrentMode];
        [self updateAssistantPrimaryStatus];
        return;
    }
    [self simulatorModeChanged:nil];
    [self applyPresentationMode];
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
            self.showControlAvailable = mode.length > 0;
            if (mode.length && !self.operatingModeChangeInFlight) {
                self.operatingModeReasonLabel.stringValue = @"Mode appliqué par CL Show Control";
                [self applyOperatingMode:mode message:nil];
            } else if (!self.operatingModeChangeInFlight) {
                self.operatingModeReasonLabel.stringValue = @"CL Show Control indisponible · mode affiché conservé localement";
                [self updateAssistantPrimaryStatus];
            }
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
    self.operatingModeReasonLabel.stringValue = @"Application à CL Show Control en cours…";
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
                self.operatingModeReasonLabel.stringValue = @"Mode inchangé · CL Show Control n’a pas validé la demande";
                self.lastTest.stringValue = error ? @"CL Show Control est indisponible" : @"Profil Ableton distant non configuré";
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
                    self.operatingModeReasonLabel.stringValue = @"Mode choisi ici et appliqué à CL Show Control";
                    [self applyOperatingMode:mode message:message];
                } else {
                    [self synchronizeOperatingMode];
                    NSString *reason = [reply[@"error"] isKindOfClass:NSString.class] ? reply[@"error"] : @"changement refusé";
                    self.lastTest.stringValue = [NSString stringWithFormat:@"Mode inchangé · %@", reason];
                    self.operatingModeReasonLabel.stringValue = @"Mode inchangé · demande refusée par CL Show Control";
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
    self.targetMenu.enabled = !self.localReturnMode;
    self.connectButton.enabled = !self.localReturnMode && names.count > 0 && !self.systemConnectRunning;
    self.connectButton.title = self.localReturnMode ? @"Non requis" : @"Connecter";
    self.connectButton.toolTip = self.localReturnMode
        ? @"Aucune connexion RTP n’est requise en mode Ableton local."
        : (names.count ? @"Demander à macOS de connecter la cible RTP sélectionnée."
                       : @"Désactivé : aucune cible RTP distante détectée.");
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
    if (self.endpointRefreshInFlight) return;
    self.endpointRefreshInFlight = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSString *> *sources = EndpointNames(YES);
        NSArray<NSString *> *destinations = EndpointNames(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.endpointRefreshInFlight = NO;
            [self applyEndpointSnapshotWithSources:sources destinations:destinations];
        });
    });
}

- (void)applyEndpointSnapshotWithSources:(NSArray<NSString *> *)sources destinations:(NSArray<NSString *> *)destinations {
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

    if (self.simulatorEndpointMenu && self.localReturnMode) {
        NSMutableArray<NSString *> *localDestinations = [NSMutableArray array];

        // En mode local, le RETURNED de production simulé doit aller
        // exclusivement vers le port virtuel dédié créé par cette application.
        if ([destinations containsObject:CLLocalReturnEndpointName]) {
            [localDestinations addObject:CLLocalReturnEndpointName];
        }

        NSString *preferred = localDestinations.count
            ? CLLocalReturnEndpointName
            : nil;

        [self.simulatorEndpointMenu removeAllItems];
        [self.simulatorEndpointMenu addItemsWithTitles:localDestinations.count
            ? localDestinations : @[@"Aucune destination MIDI locale détectée"]];
        if (preferred.length) [self.simulatorEndpointMenu selectItemWithTitle:preferred];
        self.simulatorEndpointMenu.enabled = localDestinations.count > 0;
    } else if (self.simulatorEndpointMenu) {
        NSSet<NSString *> *destinationSet = [NSSet setWithArray:destinations];
        NSMutableOrderedSet<NSString *> *localRTPNames = [NSMutableOrderedSet orderedSet];
        for (NSString *name in sources) {
            if (CLIsRTPReturnEndpointName(name) && [destinationSet containsObject:name]) [localRTPNames addObject:name];
        }
        NSArray<NSString *> *localRTPEndpoints = localRTPNames.array;
        NSString *current = self.simulatorEndpointMenu.titleOfSelectedItem;
        NSString *preferred = [localRTPEndpoints containsObject:current]
            ? current : CLPreferredLocalRTPEndpoint(localRTPEndpoints);
        [self.simulatorEndpointMenu removeAllItems];
        [self.simulatorEndpointMenu addItemsWithTitles:localRTPEndpoints.count
            ? localRTPEndpoints : @[@"Aucun endpoint RTP local détecté"]];
        if (preferred.length) [self.simulatorEndpointMenu selectItemWithTitle:preferred];
        self.simulatorEndpointMenu.enabled = localRTPEndpoints.count > 0;

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
    if (self.ownsPassiveReturnMonitor) {
        if (![self.expectedMonitorSourceName isEqualToString:CLExpectedEndpointName] ||
            ![sources containsObject:CLExpectedEndpointName]) {
            [self selectPassiveExpectedSourceNamed:CLExpectedEndpointName];
        }
        if (preferred.length &&
            (![self.returnMonitorSourceName isEqualToString:preferred] || ![sources containsObject:preferred])) {
            [self selectPassiveReturnSourceNamed:preferred];
            [self writeConsoleReturnState];
        }
    }
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
        self.returnMonitorSourceName ?: (preferred ?: @"aucune"),
        self.returnMonitorSource ? @"connectée" : @"indisponible"];
    if (self.showModeEnabled) [self updateCompactSummary];

    [self updateRoundTripPanelForCurrentMode];
    if (self.localReturnMode) {
        [self setLamp:
            [self localReturnIsAvailable] ? [NSColor systemGreenColor] : [NSColor systemOrangeColor]
            title:@"RETOUR LOCAL DÉDIÉ"
            detail:[self localReturnIsAvailable]
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
static NSString * const CLSimulatorDisplayOrderDefaultsKey = @"CLSimulatorDisplayOrderV1";
static NSString * const CLSimulatorHiddenChannelsDefaultsKey = @"CLSimulatorHiddenChannelsV1";
static NSString * const CLSimulatorGenericSignalsDefaultsKey = @"CLSimulatorGenericSignalsV1";
static NSString * const CLSimulatorAutoDeviceIDsDefaultsKey = @"CLSimulatorAutoDeviceIDsV1";
static const NSUInteger CLSimulatorJournalLimit = 500;

static NSSet<NSString *> *CLPersistedSimulatorAutoDeviceIDs(void) {
    NSArray<NSString *> *saved =
        [NSUserDefaults.standardUserDefaults
            arrayForKey:CLSimulatorAutoDeviceIDsDefaultsKey] ?: @[];

    return [NSSet setWithArray:saved];
}

static void CLPersistSimulatorAutoDeviceID(
    NSString *deviceID,
    BOOL automatic
) {
    if (!deviceID.length) return;

    NSMutableSet<NSString *> *ids =
        [CLPersistedSimulatorAutoDeviceIDs() mutableCopy];

    if (automatic)
        [ids addObject:deviceID];
    else
        [ids removeObject:deviceID];

    NSArray<NSString *> *sorted =
        [ids.allObjects sortedArrayUsingSelector:@selector(compare:)];

    [NSUserDefaults.standardUserDefaults
        setObject:sorted
        forKey:CLSimulatorAutoDeviceIDsDefaultsKey];
}

static void CLClearPersistedSimulatorAutoDeviceIDs(void) {
    [NSUserDefaults.standardUserDefaults
        removeObjectForKey:CLSimulatorAutoDeviceIDsDefaultsKey];
}

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

- (NSString *)simulatorDeviceIDForProfile:(NSDictionary *)profile {
    NSString *legacyKey = [profile[@"legacy_key"] isKindOfClass:NSString.class]
        ? profile[@"legacy_key"] : @"";
    if (legacyKey.length) return legacyKey;
    return [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
}

- (NSDictionary *)deviceProfileForSimulatorID:(NSString *)simulatorID {
    for (NSDictionary *profile in self.deviceProfiles ?: @[]) {
        if ([[self simulatorDeviceIDForProfile:profile] isEqualToString:simulatorID]) return profile;
    }
    return nil;
}

- (void)syncSimulatorDevicesFromProfiles {
    NSMutableDictionary<NSString *, NSNumber *> *savedEnabled = [NSMutableDictionary dictionary];

    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:CLSimulatorDevicesDefaultsKey];
    for (NSDictionary *item in saved ?: @[]) {
        NSString *deviceID = [item[@"id"] isKindOfClass:NSString.class] ? item[@"id"] : @"";
        if (deviceID.length) savedEnabled[deviceID] = @([item[@"enabled"] boolValue]);
    }

    for (NSDictionary *device in self.simulatorDevices ?: @[]) {
        NSString *deviceID = [device[@"id"] isKindOfClass:NSString.class] ? device[@"id"] : @"";
        if (deviceID.length) savedEnabled[deviceID] = @([device[@"enabled"] boolValue]);
    }

    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *profileDevicesByChannel = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *wantedIDs = [NSMutableSet set];

    for (NSDictionary *profile in self.deviceProfiles ?: @[]) {
        NSString *profileID = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        NSString *simulatorID = [self simulatorDeviceIDForProfile:profile];
        if (!profileID.length || !simulatorID.length) continue;

        BOOL historical =
            [profileID isEqualToString:@"console_a"] ||
            [profileID isEqualToString:@"console_b"];

        NSString *signalType = [profile[@"signal_type"] lowercaseString] ?: @"program_change";
        NSString *protocol = [profile[@"protocol"] lowercaseString] ?: @"";
        NSSet<NSString *> *simulableSignalTypes =
            [NSSet setWithObjects:@"program_change", @"control_change", @"note", nil];
        BOOL rxEnabled = [profile[@"rx"][@"enabled"] boolValue];
        BOOL profileEnabled = [profile[@"enabled"] boolValue];

        // Tous les profils MIDI activés qui participent réellement au RX
        // apparaissent automatiquement, y compris les consoles historiques.
        if (![protocol isEqualToString:@"midi"] || !profileEnabled || !rxEnabled ||
            ![simulableSignalTypes containsObject:signalType]) continue;

        if ([wantedIDs containsObject:simulatorID]) continue;

        NSString *name = [profile[@"display_name"] isKindOfClass:NSString.class]
            ? profile[@"display_name"] : simulatorID;
        NSInteger channel = [profile[@"midi_channel"] integerValue];
        if (!name.length || channel < 1 || channel > 16) continue;

        BOOL simulatorEnabled = savedEnabled[simulatorID]
            ? [savedEnabled[simulatorID] boolValue]
            : YES;

        NSMutableDictionary *device =
            [self simulatorDeviceWithID:simulatorID
                                  name:name
                               channel:channel
                               enabled:simulatorEnabled
                               builtIn:historical];

        device[@"profile_id"] = profileID;
        device[@"signal_type"] = signalType;
        device[@"managed_profile"] = @YES;
        if ([profile[@"palette"] isKindOfClass:NSDictionary.class])
            device[@"palette"] = profile[@"palette"];

        // Une ligne du banc représente toujours un canal. Le premier profil
        // éligible enrichit cette ligne ; les autres profils restent intacts.
        if (!profileDevicesByChannel[@(channel)]) profileDevicesByChannel[@(channel)] = device;
        [wantedIDs addObject:simulatorID];
    }

    NSMutableArray<NSMutableDictionary *> *synced = [NSMutableArray arrayWithCapacity:16];
    for (NSNumber *channelNumber in self.simulatorDisplayOrder ?: @[]) {
        NSInteger channel = channelNumber.integerValue;
        NSMutableDictionary *device = profileDevicesByChannel[channelNumber];
        if (!device) {
            NSString *genericID = [NSString stringWithFormat:@"test_channel_%ld", (long)channel];
            device = [self simulatorDeviceWithID:genericID
                                            name:[NSString stringWithFormat:@"Canal %ld", (long)channel]
                                         channel:channel enabled:YES builtIn:NO];
            device[@"signal_type"] = self.simulatorGenericSignalTypes[channelNumber] ?: @"program_change";
            device[@"test_only"] = @YES;
        }
        [synced addObject:device];
    }

    // Un appareil supprimé/désactivé dans Appareils ne doit pas laisser
    // tourner un simulateur fantôme.
    for (NSString *deviceID in self.simulatorTasks.allKeys.copy ?: @[]) {
        if (![wantedIDs containsObject:deviceID]) {
            NSTask *task = self.simulatorTasks[deviceID];
            if (task.running) [task terminate];
            [self.simulatorTasks removeObjectForKey:deviceID];
            [self.simulatorOutputBuffers removeObjectForKey:deviceID];
        }
    }

    self.simulatorDevices = synced;
    [self persistSimulatorDevices];
}

- (void)loadSimulatorDevices {
    NSArray *savedOrder = [NSUserDefaults.standardUserDefaults arrayForKey:CLSimulatorDisplayOrderDefaultsKey];
    NSMutableOrderedSet<NSNumber *> *validOrder = [NSMutableOrderedSet orderedSet];
    for (NSNumber *value in savedOrder ?: @[]) {
        NSInteger channel = value.integerValue;
        if (channel >= 1 && channel <= 16) [validOrder addObject:@(channel)];
    }
    for (NSInteger channel = 1; channel <= 16; channel++) [validOrder addObject:@(channel)];
    self.simulatorDisplayOrder = [validOrder.array mutableCopy];
    self.simulatorHiddenChannels = [NSMutableSet setWithArray:
        [NSUserDefaults.standardUserDefaults arrayForKey:CLSimulatorHiddenChannelsDefaultsKey] ?: @[]];
    NSDictionary *savedSignals = [NSUserDefaults.standardUserDefaults dictionaryForKey:CLSimulatorGenericSignalsDefaultsKey] ?: @{};
    self.simulatorGenericSignalTypes = [NSMutableDictionary dictionary];
    for (NSInteger channel = 1; channel <= 16; channel++) {
        NSString *signal = savedSignals[[NSString stringWithFormat:@"%ld", (long)channel]];
        if ([signal isKindOfClass:NSString.class]) self.simulatorGenericSignalTypes[@(channel)] = signal;
    }
    self.simulatorJournalEvents = [NSMutableArray array];
    self.simulatorDevices = [NSMutableArray array];
    self.simulatorTasks = [NSMutableDictionary dictionary];
    self.simulatorOutputBuffers = [NSMutableDictionary dictionary];
    [self syncSimulatorDevicesFromProfiles];
}

- (void)persistSimulatorDevices {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:self.simulatorDisplayOrder forKey:CLSimulatorDisplayOrderDefaultsKey];
    [defaults setObject:self.simulatorHiddenChannels.allObjects forKey:CLSimulatorHiddenChannelsDefaultsKey];
    NSMutableDictionary *signals = [NSMutableDictionary dictionary];
    [self.simulatorGenericSignalTypes enumerateKeysAndObjectsUsingBlock:^(NSNumber *channel, NSString *signal, BOOL *stop) {
        (void)stop; signals[channel.stringValue] = signal;
    }];
    [defaults setObject:signals forKey:CLSimulatorGenericSignalsDefaultsKey];
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
        self.simulatorActivityLabel.stringValue = [NSString stringWithFormat:@"AUTO · %lu ACTIF%@", (unsigned long)running, running > 1 ? @"S" : @""];
        self.simulatorActivityLabel.textColor = [NSColor colorWithRed:0.92 green:0.58 blue:0.26 alpha:1.0];
        self.simulatorStartButton.title = @"REDÉMARRER";
        self.simulatorStartButton.toolTip = @"Arrête puis redémarre tous les appareils de simulation activés.";
        self.simulatorStopAllButton.enabled = YES;
        self.assistantTestStatusLabel.stringValue = [NSString stringWithFormat:@"Mode test actif · %lu appareil%@ simulé%@",
            (unsigned long)running, running > 1 ? @"s" : @"", running > 1 ? @"s" : @""];
        self.assistantTestBanner.hidden = self.showModeEnabled;
    } else {
        self.simulatorActivityLabel.stringValue = @"AUTO · ARRÊTÉ";
        self.simulatorActivityLabel.textColor = NSColor.secondaryLabelColor;
        self.simulatorStartButton.title = @"DÉMARRER";
        self.simulatorStartButton.toolTip = @"Démarre les appareils de simulation activés.";
        self.simulatorStopAllButton.enabled = NO;
        self.assistantTestBanner.hidden = YES;
    }
}

- (void)showSimulatorOperatorMessage:(NSString *)message error:(BOOL)error {
    self.simulatorStatusLabel.stringValue = message ?: @"";
    self.simulatorStatusLabel.textColor = error
        ? [NSColor colorWithRed:0.95 green:0.34 blue:0.30 alpha:1.0]
        : [NSColor colorWithRed:0.95 green:0.60 blue:0.26 alpha:1.0];
}

- (NSString *)simulatorSceneTitleForProgram:(NSInteger)program channel:(NSInteger)channel {
    NSDictionary *state = channel == 1 ? self.expectedCL5State : (channel == 2 ? self.expectedQL1State : nil);
    id returnedValue = state[@"returned_midi_program"];
    NSString *title = [state[@"returned_title"] isKindOfClass:NSString.class] ? state[@"returned_title"] : nil;
    if (returnedValue && returnedValue != NSNull.null && [returnedValue integerValue] == program && title.length) return title;
    return @"Titre non résolu";
}

- (void)rebuildSimulatorDeviceRows {
    [self updateSimulatorCompactStatus];
    if (!self.simulatorDeviceRows) {
        [self updateSimulatorSafetyStatus];
        return;
    }

    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *previousValues = [NSMutableDictionary dictionary];
    for (NSString *deviceID in self.simulatorValueFields) {
        NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
        for (NSString *key in self.simulatorValueFields[deviceID]) {
            NSTextField *field = self.simulatorValueFields[deviceID][key];
            if (field.stringValue.length) values[key] = field.stringValue;
        }
        if (values.count) previousValues[deviceID] = values;
    }

    for (NSView *view in self.simulatorDeviceRows.arrangedSubviews.copy) {
        [self.simulatorDeviceRows removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    self.simulatorMemoryFields = [NSMutableDictionary dictionary];
    self.simulatorValueFields = [NSMutableDictionary dictionary];

    BOOL showAll = [self.simulatorVisibilityMenu.titleOfSelectedItem isEqualToString:@"Tous"];
    NSUInteger visibleDeviceCount = 0;
    for (NSDictionary *device in self.simulatorDevices) {
        NSString *deviceID = device[@"id"] ?: @"";
        NSString *deviceName = device[@"name"] ?: @"Device";
        NSInteger channel = [device[@"channel"] integerValue];
        BOOL hidden = [self.simulatorHiddenChannels containsObject:@(channel)];
        if (hidden && !showAll) continue;
        visibleDeviceCount += 1;
        NSString *signalType = [device[@"signal_type"] lowercaseString] ?: @"program_change";
        BOOL programChange = [signalType isEqualToString:@"program_change"];
        BOOL running = self.simulatorTasks[deviceID].running;

        NSDictionary *profile = [self deviceProfileForSimulatorID:deviceID];
        NSString *protocol = [profile[@"protocol"] isKindOfClass:NSString.class]
            ? [profile[@"protocol"] lowercaseString] : @"";
        NSString *libraryID = [profile[@"library"] isKindOfClass:NSString.class]
            ? [profile[@"library"] lowercaseString] : @"";
        BOOL hasRelevantLibrary = programChange &&
            [protocol isEqualToString:@"midi"] && libraryID.length > 0;
        NSDictionary *palette = [profile[@"palette"] isKindOfClass:NSDictionary.class]
            ? profile[@"palette"] : @{};

        NSColor *accent =
            [self deviceColorFromHex:palette[@"accent"]
                            fallback:[NSColor colorWithRed:0.31 green:0.53 blue:0.78 alpha:1.0]];
        NSColor *identity =
            [self deviceColorFromHex:palette[@"base"] fallback:accent];
        NSColor *background =
            [[NSColor colorWithRed:0.070 green:0.082 blue:0.105 alpha:1.0]
                blendedColorWithFraction:0.18 ofColor:identity];

        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 686, 28)];
        row.wantsLayer = YES;
        row.layer.cornerRadius = 5;
        row.layer.backgroundColor = background.CGColor;
        row.layer.borderColor = [NSColor colorWithWhite:0.25 alpha:0.42].CGColor;
        row.layer.borderWidth = 0.5;

        CLSimulatorDragButton *drag = [[CLSimulatorDragButton alloc] initWithFrame:NSMakeRect(5, 3, 24, 22)];
        drag.title = @"⠿"; drag.bezelStyle = NSBezelStyleTexturedRounded;
        drag.identifier = deviceID; drag.tag = channel; drag.midiChannel = channel;
        drag.toolTip = @"Faire glisser pour réordonner cette ligne";
        [row addSubview:drag];

        NSView *stripe = [[NSView alloc] initWithFrame:NSMakeRect(31, 3, 3, 22)];
        stripe.wantsLayer = YES;
        stripe.layer.cornerRadius = 1.5;
        stripe.layer.backgroundColor = accent.CGColor;
        [row addSubview:stripe];

        NSTextField *name = [self label:deviceName
                                  frame:NSMakeRect(40, 5, 108, 17)
                                   size:10
                                   bold:YES];
        name.textColor = accent;
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [row addSubview:name];

        NSTextField *channelLabel =
            [self label:[NSString stringWithFormat:@"Ch.%ld", (long)channel]
                  frame:NSMakeRect(150, 5, 38, 17)
                   size:8
                   bold:NO];
        channelLabel.textColor = NSColor.secondaryLabelColor;
        [row addSubview:channelLabel];

        NSMutableDictionary<NSString *, NSTextField *> *valueFields = [NSMutableDictionary dictionary];
        self.simulatorValueFields[deviceID] = valueFields;
        NSDictionary<NSString *, NSString *> *savedValues = previousValues[deviceID] ?: @{};
        NSString *firstLabel = programChange ? @"PC" :
            ([signalType isEqualToString:@"control_change"] ? @"CC" : @"Note");
        if ([device[@"test_only"] boolValue]) {
            NSPopUpButton *typeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(190, 2, 64, 24) pullsDown:NO];
            [typeMenu addItemsWithTitles:@[@"PC", @"CC", @"Note"]];
            [typeMenu selectItemWithTitle:programChange ? @"PC" : ([signalType isEqualToString:@"control_change"] ? @"CC" : @"Note")];
            typeMenu.identifier = deviceID; typeMenu.tag = channel; typeMenu.target = self;
            typeMenu.action = @selector(simulatorGenericSignalChanged:);
            [row addSubview:typeMenu];
        } else {
            [row addSubview:[self label:firstLabel frame:NSMakeRect(202, 5, 45, 17) size:8 bold:YES]];
        }

        NSTextField *data1Field = [[NSTextField alloc] initWithFrame:NSMakeRect(260, 3, 46, 22)];
        NSString *data1Key = programChange ? @"memory" :
            ([signalType isEqualToString:@"control_change"] ? @"controller" : @"note");
        NSString *savedData1 = savedValues[data1Key];
        if (savedData1.length) data1Field.stringValue = savedData1;
        else if (programChange && [deviceID isEqualToString:@"cl5"]) data1Field.stringValue = @"81";
        else if (programChange && [deviceID isEqualToString:@"ql1"]) data1Field.stringValue = @"78";
        else data1Field.stringValue = programChange ? @"1" :
            ([signalType isEqualToString:@"note"] ? @"60" : @"1");
        data1Field.alignment = NSTextAlignmentCenter;
        valueFields[data1Key] = data1Field;
        if (programChange) self.simulatorMemoryFields[deviceID] = data1Field;
        [row addSubview:data1Field];

        if (!programChange) {
            BOOL controlChange = [signalType isEqualToString:@"control_change"];
            NSString *data2Key = controlChange ? @"value" : @"velocity";
            NSString *data2Label = controlChange ? @"Val" : @"Vel";
            [row addSubview:[self label:data2Label frame:NSMakeRect(312, 5, 28, 17) size:8 bold:NO]];
            NSTextField *data2Field = [[NSTextField alloc] initWithFrame:NSMakeRect(340, 3, 46, 22)];
            data2Field.stringValue = savedValues[data2Key] ?: (controlChange ? @"127" : @"100");
            data2Field.alignment = NSTextAlignmentCenter;
            valueFields[data2Key] = data2Field;
            [row addSubview:data2Field];
        } else if (hasRelevantLibrary) {
            NSButton *library =
                [self accentButton:@"Bibliothèque…"
                             frame:NSMakeRect(312, 3, 92, 22)
                            action:@selector(selectConsoleLibrary:)
                             color:[NSColor colorWithWhite:0.24 alpha:1.0]];
            library.identifier = libraryID;
            library.font = [NSFont systemFontOfSize:8.0];
            library.toolTip = [NSString stringWithFormat:@"Modifier la bibliothèque %@", libraryID.uppercaseString];
            [row addSubview:library];
        }

        NSButton *send =
            [self accentButton:@"Envoyer"
                         frame:NSMakeRect(414, 3, 78, 22)
                        action:@selector(sendSimulatorMemory:)
                         color:accent];
        send.identifier = deviceID;
        send.tag = channel;
        [row addSubview:send];

        NSButton *startStop =
            [self button:running ? @"■" : @"▶"
                   frame:NSMakeRect(500, 3, 58, 22)
                  action:@selector(toggleSimulatorDeviceRunning:)];
        startStop.identifier = deviceID;
        startStop.enabled = programChange;
        startStop.title = running ? @"■ Stop" : @"▶ Auto";
        startStop.font = [NSFont systemFontOfSize:8.0];
        startStop.accessibilityLabel = running ? @"Arrêter l’automatisation de cette ligne" : @"Démarrer l’automatisation de cette ligne";
        startStop.toolTip = programChange
            ? (running ? @"Arrêter ce simulateur" : @"Démarrer ce simulateur")
            : @"Auto disponible uniquement pour Program Change · utiliser Envoyer";
        [row addSubview:startStop];

        NSTextField *state =
            [self label:running ? @"●" : @""
                  frame:NSMakeRect(564, 6, 14, 16)
                   size:9
                   bold:YES];
        state.textColor = running
            ? [NSColor colorWithRed:0.35 green:0.88 blue:0.55 alpha:1.0]
            : NSColor.secondaryLabelColor;
        state.toolTip = running ? @"Automatisation active" : @"Automatisation arrêtée";
        [row addSubview:state];

        NSButton *eye = [self button:hidden ? @"Afficher" : @"Masquer" frame:NSMakeRect(584, 3, 92, 22) action:@selector(toggleSimulatorRowVisibility:)];
        eye.identifier = deviceID; eye.tag = channel;
        eye.toolTip = hidden ? @"Afficher cette ligne dans la vue Visibles" : @"Masquer cette ligne sans désactiver son profil";
        eye.font = [NSFont systemFontOfSize:8.0];
        [row addSubview:eye];
        row.alphaValue = hidden ? 0.48 : 1.0;

        [self.simulatorDeviceRows addArrangedSubview:row];
        [row.widthAnchor constraintEqualToConstant:686].active = YES;
        [row.heightAnchor constraintEqualToConstant:28].active = YES;
    }

    const CGFloat rowHeight = 28.0;
    const CGFloat rowSpacing = 3.0;
    CGFloat visibleHeight = MAX(1.0, self.simulatorDevicesScroll.contentSize.height);
    NSUInteger deviceCount = visibleDeviceCount;
    CGFloat rowsHeight = deviceCount
        ? (deviceCount * rowHeight) + ((deviceCount - 1) * rowSpacing)
        : 0.0;
    CGFloat documentHeight = MAX(visibleHeight, rowsHeight);

    self.simulatorDeviceRows.frame =
        NSMakeRect(0, 0, 686, documentHeight);
    self.simulatorDevicesScroll.hasVerticalScroller = documentHeight > visibleHeight;
    [self.simulatorDevicesScroll.contentView scrollToPoint:
        NSMakePoint(0, MAX(0.0, documentHeight - visibleHeight))];
    [self.simulatorDevicesScroll reflectScrolledClipView:
        self.simulatorDevicesScroll.contentView];

    [self updateSimulatorSafetyStatus];
}

- (void)moveSimulatorChannel:(NSInteger)midiChannel toDisplayIndex:(NSUInteger)requestedIndex {
    NSNumber *channel = @(midiChannel);
    NSUInteger index = [self.simulatorDisplayOrder indexOfObject:channel];
    if (index == NSNotFound) return;
    [self.simulatorDisplayOrder removeObjectAtIndex:index];
    NSUInteger destination = MIN(requestedIndex, self.simulatorDisplayOrder.count);
    [self.simulatorDisplayOrder insertObject:channel atIndex:destination];
    [self syncSimulatorDevicesFromProfiles];
    [self rebuildSimulatorDeviceRows];
}

- (void)toggleSimulatorRowVisibility:(NSButton *)sender {
    NSNumber *channel = @(sender.tag);
    if ([self.simulatorHiddenChannels containsObject:channel])
        [self.simulatorHiddenChannels removeObject:channel];
    else
        [self.simulatorHiddenChannels addObject:channel];
    [self persistSimulatorDevices];
    [self rebuildSimulatorDeviceRows];
}

- (void)simulatorVisibilityChanged:(id)sender { (void)sender; [self rebuildSimulatorDeviceRows]; }

- (void)resetSimulatorDisplay:(id)sender {
    (void)sender;
    [self.simulatorDisplayOrder removeAllObjects];
    for (NSInteger channel = 1; channel <= 16; channel++) [self.simulatorDisplayOrder addObject:@(channel)];
    [self.simulatorHiddenChannels removeAllObjects];
    [self persistSimulatorDevices];
    [self syncSimulatorDevicesFromProfiles];
    [self rebuildSimulatorDeviceRows];
    [self appendSimulatorJournalKind:@"SYS" message:@"Affichage réinitialisé"];
}

- (void)simulatorGenericSignalChanged:(NSPopUpButton *)sender {
    NSDictionary *mapping = @{@"PC": @"program_change", @"CC": @"control_change", @"Note": @"note"};
    self.simulatorGenericSignalTypes[@(sender.tag)] = mapping[sender.titleOfSelectedItem] ?: @"program_change";
    [self persistSimulatorDevices];
    [self syncSimulatorDevicesFromProfiles];
    [self rebuildSimulatorDeviceRows];
}

- (void)appendSimulatorJournalKind:(NSString *)kind message:(NSString *)message {
    if (!self.simulatorJournalEvents) self.simulatorJournalEvents = [NSMutableArray array];
    static NSDateFormatter *formatter;
    if (!formatter) { formatter = [[NSDateFormatter alloc] init]; formatter.dateFormat = @"HH:mm:ss.SSS"; }
    NSString *line = [NSString stringWithFormat:@"%@  %@  %@", [formatter stringFromDate:NSDate.date], kind, message ?: @""];
    [self.simulatorJournalEvents addObject:line];
    while (self.simulatorJournalEvents.count > CLSimulatorJournalLimit)
        [self.simulatorJournalEvents removeObjectAtIndex:0];
    self.simulatorJournalView.string = [self.simulatorJournalEvents componentsJoinedByString:@"\n"];
    [self.simulatorJournalView scrollRangeToVisible:NSMakeRange(self.simulatorJournalView.string.length, 0)];
}

- (void)clearSimulatorJournal:(id)sender {
    (void)sender; [self.simulatorJournalEvents removeAllObjects]; self.simulatorJournalView.string = @"";
}

- (void)copySimulatorJournal:(id)sender {
    (void)sender;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:self.simulatorJournalView.string ?: @"" forType:NSPasteboardTypeString];
}

- (void)openSimulatorWindow:(id)sender {
    (void)sender;
    if (self.simulatorWindow) {
        [self.simulatorWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }

    self.simulatorWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 760, 700)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.simulatorWindow.title = @"CL MIDI Network Manager · Banc de test MIDI";
    self.simulatorWindow.minSize = NSMakeSize(760, 700);
    self.simulatorWindow.delegate = self;
    self.simulatorWindow.contentView.wantsLayer = YES;
    self.simulatorWindow.contentView.layer.backgroundColor =
        [NSColor colorWithRed:0.045 green:0.052 blue:0.066 alpha:1.0].CGColor;
    [self createIntegratedSimulatorPanelInView:self.simulatorWindow.contentView];
    [self refreshEndpoints];
    [self.simulatorWindow center];
    [self.simulatorWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)createIntegratedSimulatorPanelInView:(NSView *)parent {
    NSView *content = self.simulatorPanel = [[NSView alloc] initWithFrame:NSMakeRect(16, 16, 728, 668)];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    content.wantsLayer = YES; content.layer.cornerRadius = 12; content.layer.borderWidth = 1;
    content.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.060 blue:0.045 alpha:1.0].CGColor;
    content.layer.borderColor = [NSColor colorWithRed:0.72 green:0.43 blue:0.18 alpha:0.72].CGColor;
    [parent addSubview:content];

    NSTextField *title = [self label:@"BANC DE TEST MIDI · 16 CANAUX" frame:NSMakeRect(14, 638, 250, 18) size:11 bold:YES];
    title.autoresizingMask = NSViewMinYMargin;
    title.textColor = [NSColor colorWithRed:1.0 green:0.68 blue:0.28 alpha:1.0];
    [content addSubview:title];

    self.simulatorStopAllButton =
        [self button:@"■ Tout arrêter"
               frame:NSMakeRect(602, 636, 112, 22)
              action:@selector(stopIntegratedSimulator:)];
    self.simulatorStopAllButton.font = [NSFont systemFontOfSize:8.0];
    self.simulatorStopAllButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    self.simulatorStopAllButton.toolTip = @"Arrêter uniquement toutes les simulations actives";
    [content addSubview:self.simulatorStopAllButton];

    NSTextField *modeAutoLabel = [self label:@"MODE AUTO" frame:NSMakeRect(14, 606, 74, 14) size:8 bold:YES];
    modeAutoLabel.autoresizingMask = NSViewMinYMargin; [content addSubview:modeAutoLabel];
    self.simulatorModeLabel = [self label:@"" frame:NSMakeRect(14, 580, 230, 22) size:9 bold:YES];
    self.simulatorModeLabel.autoresizingMask = NSViewMinYMargin;
    self.simulatorModeLabel.textColor = [NSColor colorWithRed:0.92 green:0.58 blue:0.26 alpha:1.0];
    [content addSubview:self.simulatorModeLabel];

    self.simulatorEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(250, 578, 180, 24) pullsDown:NO];
    [self.simulatorEndpointMenu addItemWithTitle:CLLocalReturnEndpointName];
    self.simulatorEndpointMenu.target = self;
    self.simulatorEndpointMenu.action = @selector(simulatorEndpointChanged:);
    self.simulatorEndpointMenu.autoresizingMask = NSViewMinYMargin;
    [self stylePopup:self.simulatorEndpointMenu accent:[NSColor colorWithRed:0.44 green:0.76 blue:1.0 alpha:1.0]];
    [content addSubview:self.simulatorEndpointMenu];
    NSTextField *destinationLabel = [self label:@"DESTINATION" frame:NSMakeRect(254, 606, 120, 14) size:8 bold:YES];
    destinationLabel.autoresizingMask = NSViewMinYMargin; [content addSubview:destinationLabel];

    NSTextField *sourceAutoLabel = [self label:@"SOURCE AUTO" frame:NSMakeRect(442, 606, 120, 14) size:8 bold:YES];
    sourceAutoLabel.autoresizingMask = NSViewMinYMargin; [content addSubview:sourceAutoLabel];
    self.simulatorInputEndpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(438, 578, 156, 24) pullsDown:NO];
    [self.simulatorInputEndpointMenu addItemWithTitle:@"Aucune"];
    self.simulatorInputEndpointMenu.target = self;
    self.simulatorInputEndpointMenu.action = @selector(simulatorInputEndpointChanged:);
    self.simulatorInputEndpointMenu.autoresizingMask = NSViewMinYMargin;
    [self stylePopup:self.simulatorInputEndpointMenu accent:[NSColor colorWithRed:0.62 green:0.62 blue:0.68 alpha:1.0]];
    [content addSubview:self.simulatorInputEndpointMenu];

    self.simulatorMemoryFields = [NSMutableDictionary dictionary];
    self.simulatorValueFields = [NSMutableDictionary dictionary];

    self.simulatorDevicesScroll =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(14, 266, 700, 300)];
    self.simulatorDevicesScroll.hasHorizontalScroller = NO;
    self.simulatorDevicesScroll.hasVerticalScroller = YES;
    self.simulatorDevicesScroll.autohidesScrollers = NO;
    self.simulatorDevicesScroll.scrollerStyle = NSScrollerStyleLegacy;
    self.simulatorDevicesScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.simulatorDevicesScroll.borderType = NSNoBorder;

    self.simulatorDeviceRows =
        [[CLSimulatorRowsView alloc] initWithFrame:NSMakeRect(0, 0, 686, 300)];
    ((CLSimulatorRowsView *)self.simulatorDeviceRows).reorderDelegate = self;
    self.simulatorDeviceRows.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.simulatorDeviceRows.alignment = NSLayoutAttributeLeading;
    self.simulatorDeviceRows.distribution = NSStackViewDistributionFill;
    self.simulatorDeviceRows.spacing = 2;
    self.simulatorDeviceRows.translatesAutoresizingMaskIntoConstraints = YES;

    self.simulatorDevicesScroll.documentView = self.simulatorDeviceRows;
    [content addSubview:self.simulatorDevicesScroll];

    NSTextField *delayLabel =
        [self label:@"Délai"
              frame:NSMakeRect(272, 638, 34, 18)
               size:8
               bold:NO];
    delayLabel.autoresizingMask = NSViewMinYMargin;
    [content addSubview:delayLabel];

    self.simulatorDelayField =
        [[NSTextField alloc] initWithFrame:NSMakeRect(306, 635, 42, 24)];
    self.simulatorDelayField.stringValue = @"80";
    self.simulatorDelayField.alignment = NSTextAlignmentCenter;
    self.simulatorDelayField.toolTip = @"Délai utilisé par l’automatisation des Program Change";
    self.simulatorDelayField.autoresizingMask = NSViewMinYMargin;
    [content addSubview:self.simulatorDelayField];

    NSTextField *msLabel =
        [self label:@"ms"
              frame:NSMakeRect(350, 638, 20, 18)
               size:8
               bold:NO];
    msLabel.autoresizingMask = NSViewMinYMargin;
    [content addSubview:msLabel];

    self.simulatorVisibilityMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(602, 578, 112, 24) pullsDown:NO];
    [self.simulatorVisibilityMenu addItemsWithTitles:@[@"Visibles", @"Tous"]];
    self.simulatorVisibilityMenu.target = self; self.simulatorVisibilityMenu.action = @selector(simulatorVisibilityChanged:);
    self.simulatorVisibilityMenu.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:self.simulatorVisibilityMenu];
    NSTextField *visibilityLabel = [self label:@"AFFICHAGE" frame:NSMakeRect(606, 606, 104, 14) size:8 bold:YES];
    visibilityLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin; [content addSubview:visibilityLabel];
    NSButton *resetDisplay = [self button:@"Réinitialiser l’affichage" frame:NSMakeRect(14, 236, 150, 22) action:@selector(resetSimulatorDisplay:)];
    resetDisplay.font = [NSFont systemFontOfSize:8.0]; [content addSubview:resetDisplay];

    self.simulatorStatusLabel =
        [self label:@"PRÊT · SÉLECTIONNEZ UN CANAL"
              frame:NSMakeRect(174, 218, 540, 40)
               size:16
               bold:YES];
    self.simulatorStatusLabel.alignment = NSTextAlignmentCenter;
    self.simulatorStatusLabel.textColor =
        [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0];
    [content addSubview:self.simulatorStatusLabel];

    self.simulatorActivityLabel = [self label:@"AUTO · ARRÊTÉ" frame:NSMakeRect(14, 218, 150, 16) size:8 bold:YES];
    self.simulatorActivityLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.simulatorActivityLabel];

    NSTextField *journalTitle = [self label:@"JOURNAL DU BANC · MÉMOIRE, 500 ÉVÉNEMENTS MAX." frame:NSMakeRect(14, 194, 400, 16) size:9 bold:YES];
    journalTitle.textColor = [NSColor colorWithRed:0.42 green:0.80 blue:0.88 alpha:1.0]; [content addSubview:journalTitle];
    NSButton *copyJournal = [self button:@"Copier" frame:NSMakeRect(570, 190, 68, 22) action:@selector(copySimulatorJournal:)];
    NSButton *clearJournal = [self button:@"Effacer" frame:NSMakeRect(646, 190, 68, 22) action:@selector(clearSimulatorJournal:)];
    [content addSubview:copyJournal]; [content addSubview:clearJournal];
    NSScrollView *journalScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, 14, 700, 170)];
    journalScroll.hasVerticalScroller = YES; journalScroll.autohidesScrollers = YES;
    self.simulatorJournalView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 684, 170)];
    self.simulatorJournalView.editable = NO; self.simulatorJournalView.selectable = YES;
    self.simulatorJournalView.font = [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightRegular];
    self.simulatorJournalView.backgroundColor = [NSColor colorWithWhite:0.025 alpha:0.72];
    self.simulatorJournalView.textColor = [NSColor colorWithWhite:0.78 alpha:1.0];
    journalScroll.documentView = self.simulatorJournalView; [content addSubview:journalScroll];

    self.simulatorStartButton = nil;
    self.simulatorCL5MemoryField = nil;
    self.simulatorQL1MemoryField = nil;

    [self rebuildSimulatorDeviceRows];

    [self simulatorModeChanged:nil];
}

- (void)sendSimulatorMemory:(NSButton *)sender {
    NSString *deviceID = sender.identifier ?: @"";
    NSMutableDictionary *device = [self simulatorDeviceForID:deviceID];
    NSInteger channel = device ? [device[@"channel"] integerValue] : sender.tag;
    NSString *deviceName = device ? (device[@"name"] ?: @"Device") : [NSString stringWithFormat:@"Ch.%ld", (long)channel];
    NSString *operatorName = deviceName.uppercaseString;
    NSString *signalType = [device[@"signal_type"] lowercaseString] ?: @"program_change";
    BOOL programChange = [signalType isEqualToString:@"program_change"];
    NSDictionary<NSString *, NSTextField *> *fields = self.simulatorValueFields[deviceID];
    NSString *data1Key = programChange ? @"memory" :
        ([signalType isEqualToString:@"control_change"] ? @"controller" : @"note");
    NSString *data2Key = [signalType isEqualToString:@"control_change"] ? @"value" : @"velocity";
    NSInteger data1Input = fields[data1Key].integerValue;
    NSInteger data2Input = programChange ? -1 : fields[data2Key].integerValue;
    BOOL valid = channel >= 1 && channel <= 16 && (programChange
        ? (data1Input >= 1 && data1Input <= 128)
        : (data1Input >= 0 && data1Input <= 127 && data2Input >= 0 && data2Input <= 127));
    if (!valid) {
        [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · VALEUR MIDI INVALIDE", operatorName] error:YES];
        [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  %@  ERREUR valeur hors plage", deviceName, (long)channel, programChange ? @"PC" : signalType.uppercaseString]];
        return;
    }
    NSString *endpoint = self.simulatorEndpointMenu.titleOfSelectedItem ?: @"";
    if (self.localReturnMode &&
        (![endpoint isEqualToString:CLLocalReturnEndpointName] ||
         ![EndpointNames(NO) containsObject:endpoint])) {
        [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
        [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  → %@  ERREUR destination", deviceName, (long)channel, endpoint]];
        return;
    }
    if (!self.localReturnMode && ![CLLocalRTPEndpointNames() containsObject:endpoint]) {
        [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
        [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  → %@  ERREUR endpoint RTP", deviceName, (long)channel, endpoint]];
        return;
    }
    if (self.localReturnMode || !programChange) {
        // CL MIDI Return Test est volontairement une destination virtuelle
        // uniquement. Un envoi local ne doit donc pas exiger de source
        // CoreMIDI homonyme ni passer par CLMIDIRoundTripTester.
        MIDIEndpointRef destination = 0;
        for (ItemCount index = 0; index < MIDIGetNumberOfDestinations(); index++) {
            MIDIEndpointRef item = MIDIGetDestination(index);
            if ([EndpointName(item) isEqualToString:endpoint]) { destination = item; break; }
        }
        if (!self.simulatorMidiClient) {
            OSStatus clientStatus = MIDIClientCreate(
                CFSTR("CL Simulator TX"), NULL, NULL, &_simulatorMidiClient);
            if (clientStatus != noErr || !self.simulatorMidiClient) {
                [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
                [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  ERREUR MIDIClientCreate %d", deviceName, (long)channel, (int)clientStatus]];
                return;
            }
        }
        if (!self.simulatorMidiOutputPort) {
            OSStatus portStatus = MIDIOutputPortCreate(
                self.simulatorMidiClient,
                CFSTR("CL Simulator TX Output"),
                &_simulatorMidiOutputPort
            );
            if (portStatus != noErr || !self.simulatorMidiOutputPort) {
                [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
                CLAppendDiagnostic(
                    @"integrated-simulator-manual-send-error",
                    [NSString stringWithFormat:@"stage=output-port status=%d channel=%ld memory=%ld endpoint=%@",
                     (int)portStatus, (long)channel, (long)data1Input, endpoint]
                );
                [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  ERREUR MIDIOutputPortCreate %d", deviceName, (long)channel, (int)portStatus]];
                return;
            }
        }

        UInt8 data1 = (UInt8)(programChange ? data1Input - 1 : data1Input);
        UInt8 statusByte = (UInt8)((programChange ? 0xC0 :
            ([signalType isEqualToString:@"control_change"] ? 0xB0 : 0x90)) |
            ((channel - 1) & 0x0F));

        MIDIPacketList packetList;
        packetList.numPackets = 1;
        packetList.packet[0].timeStamp = 0;
        packetList.packet[0].length = programChange ? 2 : 3;
        packetList.packet[0].data[0] = statusByte;
        packetList.packet[0].data[1] = data1;
        if (!programChange) packetList.packet[0].data[2] = (UInt8)data2Input;

        OSStatus sendStatus = MIDISend(self.simulatorMidiOutputPort, destination, &packetList);

        if (sendStatus != noErr) {
            [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
            CLAppendDiagnostic(
                @"integrated-simulator-manual-send-error",
                [NSString stringWithFormat:@"stage=send status=%d channel=%ld memory=%ld midi_program=%u endpoint=%@",
                 (int)sendStatus, (long)channel, (long)data1Input, (unsigned)data1, endpoint]
            );
            [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  %@  → %@  ERREUR %d", deviceName, (long)channel, signalType.uppercaseString, endpoint, (int)sendStatus]];
            return;
        }

        if (programChange) [self recordSimulatorProgram:data1 channel:channel];
        NSString *operatorMessage = programChange
            ? [NSString stringWithFormat:@"%@ · MÉMOIRE %03ld ENVOYÉE", operatorName, (long)data1Input]
            : [signalType isEqualToString:@"control_change"]
            ? [NSString stringWithFormat:@"%@ · CC %ld = %ld ENVOYÉ", operatorName, (long)data1Input, (long)data2Input]
            : [NSString stringWithFormat:@"%@ · NOTE %ld · VEL %ld ENVOYÉE", operatorName, (long)data1Input, (long)data2Input];
        [self showSimulatorOperatorMessage:operatorMessage error:NO];
        NSString *values = programChange
            ? [NSString stringWithFormat:@"mémoire %ld", (long)data1Input]
            : [NSString stringWithFormat:@"%ld = %ld", (long)data1Input, (long)data2Input];
        [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  %@  %@  → %@  OK", deviceName, (long)channel, programChange ? @"PC" : ([signalType isEqualToString:@"control_change"] ? @"CC" : @"NOTE"), values, endpoint]];

        CLAppendDiagnostic(
            @"integrated-simulator-manual-send",
            [NSString stringWithFormat:@"status=0 type=%@ channel=%ld data1=%u data2=%ld endpoint=%@",
             signalType, (long)channel, (unsigned)data1, (long)data2Input, endpoint]
        );
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLYamahaConsoleSimulator"]];
    task.arguments = @[@"--label", deviceName,
                       @"--channel", [NSString stringWithFormat:@"%ld", (long)channel],
                       @"--transport", @"rtp", @"--endpoint", endpoint,
                       @"--send-program", [NSString stringWithFormat:@"%ld", (long)data1Input], @"--no-echo"];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · ÉCHEC D’ENVOI MIDI", operatorName] error:YES];
        [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  PC  → %@  ERREUR %@", deviceName, (long)channel, endpoint, error.localizedDescription]];
        return;
    }
    [self showSimulatorOperatorMessage:[NSString stringWithFormat:@"%@ · MÉMOIRE %03ld ENVOYÉE", operatorName, (long)data1Input] error:NO];
    [self appendSimulatorJournalKind:@"TX" message:[NSString stringWithFormat:@"%@  Ch.%ld  PC  mémoire %ld  → %@  OK", deviceName, (long)channel, (long)data1Input, endpoint]];
    CLAppendDiagnostic(@"integrated-simulator-manual-send", [NSString stringWithFormat:@"channel=%ld memory=%ld endpoint=%@", (long)channel, (long)data1Input, endpoint]);
}

- (void)simulatorModeChanged:(id)sender {
    (void)sender;
    self.simulatorModeLabel.stringValue = self.localReturnMode ? @"Ableton local · dérivé du mode général" : @"Ableton distant · dérivé du mode général";
    [self updateRoundTripPanelForCurrentMode];
    if (self.localReturnMode) {
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
        self.returnMonitorSourceName = nil;
    }

    NSString *preferred =
        CLPreferredConsoleReturnEndpoint(EndpointNames(YES));
    if (preferred.length) {
        [self.endpointMenu selectItemWithTitle:preferred];
        [self selectPassiveReturnSourceNamed:preferred];
    }

    if (self.localReturnMode && !preferred.length) {
        self.returnMonitorStatus =
            self.localReturnDestination ? noErr : kMIDIUnknownEndpoint;
    }
    [self writeConsoleReturnState];

    [self refreshEndpoints];
}

- (void)simulatorEndpointChanged:(id)sender {
    (void)sender;
    NSString *endpoint = self.simulatorEndpointMenu.titleOfSelectedItem ?: @"";
    if (self.localReturnMode && !CLIsProtectedDeviceTestEndpoint(endpoint)) {
        [NSUserDefaults.standardUserDefaults setObject:endpoint forKey:CLLocalSimulatorDestinationPreference];
    } else if ([CLLocalRTPEndpointNames() containsObject:endpoint]) {
        [NSUserDefaults.standardUserDefaults setObject:endpoint forKey:@"simulatorLocalRtpEndpoint"];
    }
    if (endpoint.length) [self appendSimulatorJournalKind:@"SYS" message:[NSString stringWithFormat:@"Destination → %@", endpoint]];
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
                if (midiProgram >= 0 && midiProgram <= 127) {
                    [strongSelf recordSimulatorProgram:midiProgram deviceID:deviceID];
                    NSMutableDictionary *observed = [strongSelf simulatorDeviceForID:deviceID];
                    [strongSelf appendSimulatorJournalKind:@"RX" message:[NSString stringWithFormat:@"%@  Ch.%@  PC  mémoire %ld  ← %@  OK", observed[@"name"] ?: deviceID, observed[@"channel"] ?: @0, (long)midiProgram + 1, input.length ? input : @"source auto"]];
                }
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
    NSString *requiredEndpoint = selectedEndpoint;
    if (local && ![CLSimulatorInputEndpointNames() containsObject:CLExpectedEndpointName]) {
        self.simulatorStatusLabel.stringValue = @"EXPECTED absent : Gestionnaire IAC Bus 1 introuvable";
        self.simulatorStatusLabel.textColor = NSColor.systemRedColor;
        return NO;
    }
    if (local &&
        (![requiredEndpoint isEqualToString:CLLocalReturnEndpointName] ||
         ![EndpointNames(NO) containsObject:requiredEndpoint])) {
        self.simulatorStatusLabel.stringValue = @"Destination MIDI locale indisponible";
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
    if (![[device[@"signal_type"] lowercaseString] isEqualToString:@"program_change"]) return;
    NSString *transport, *endpoint; NSInteger delay;
    if (![self simulatorTransport:&transport endpoint:&endpoint delay:&delay]) return;
    NSTask *task =
        [self launchSimulatorDevice:device
                          transport:transport
                           endpoint:endpoint
                              delay:delay];

    if (task.running)
        CLPersistSimulatorAutoDeviceID(device[@"id"], YES);

    [self rebuildSimulatorDeviceRows];
    [self updateSimulatorCompactStatus];
}

- (void)stopSimulatorDeviceID:(NSString *)deviceID {
    NSTask *task = self.simulatorTasks[deviceID];

    if (task.running)
        [task terminate];

    [self.simulatorTasks removeObjectForKey:deviceID];

    // STOP volontaire : ne pas restaurer cette ligne.
    CLPersistSimulatorAutoDeviceID(deviceID, NO);

    [self rebuildSimulatorDeviceRows];
    [self updateSimulatorCompactStatus];
}

- (void)updateSimulatorCompactStatus {
    if (!self.simulatorCompactStatus)
        return;

    NSUInteger targetCount = 0;
    NSUInteger runningCount = 0;

    for (NSMutableDictionary *device in self.simulatorDevices ?: @[]) {
        BOOL enabled = [device[@"enabled"] boolValue];
        BOOL programChange =
            [[device[@"signal_type"] lowercaseString]
                isEqualToString:@"program_change"];

        if (!enabled || !programChange)
            continue;

        targetCount++;

        NSString *deviceID = device[@"id"] ?: @"";
        NSTask *task =
            deviceID.length ? self.simulatorTasks[deviceID] : nil;

        if (task.running)
            runningCount++;
    }

    if (!targetCount) {
        self.simulatorCompactStatus.stringValue =
            @"● RETOURS AUTO —";
        self.simulatorCompactStatus.textColor =
            NSColor.secondaryLabelColor;
        return;
    }

    self.simulatorCompactStatus.stringValue =
        [NSString stringWithFormat:@"● RETOURS AUTO %lu/%lu",
         (unsigned long)runningCount,
         (unsigned long)targetCount];

    if (runningCount == targetCount) {
        self.simulatorCompactStatus.textColor =
            [NSColor colorWithRed:0.35
                            green:0.88
                             blue:0.55
                            alpha:1.0];
    } else if (runningCount > 0) {
        self.simulatorCompactStatus.textColor =
            NSColor.systemOrangeColor;
    } else {
        self.simulatorCompactStatus.textColor =
            NSColor.systemRedColor;
    }
}

- (void)restorePersistedSimulatorAutoDevices {
    if (self.backgroundMonitorOnly)
        return;

    /*
     AUTO LOCAL PAR DÉFAUT

     Au démarrage normal, tous les devices Program Change activés
     doivent lancer leur simulateur de retour.

     Un Stop reste valable pour la session courante, mais ne doit
     pas transformer le prochain lancement en AUTO 0/N.
    */
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];

    for (NSMutableDictionary *device in self.simulatorDevices ?: @[]) {
        if (![device[@"enabled"] boolValue])
            continue;

        if (![[device[@"signal_type"] lowercaseString]
                isEqualToString:@"program_change"])
            continue;

        NSString *deviceID = device[@"id"] ?: @"";

        if (deviceID.length)
            [wanted addObject:deviceID];
    }

    if (!wanted.count) {
        [self updateSimulatorCompactStatus];
        return;
    }

    /*
     Sécurité :
     restauration automatique uniquement dans le chemin LOCAL
     déjà validé :
       EXPECTED = Gestionnaire IAC Bus 1
       RETURNED = CL MIDI Return Test
    */
    if (!self.localReturnMode) {
        [self updateSimulatorCompactStatus];
        return;
    }

    BOOL endpointsReady =
        [CLSimulatorInputEndpointNames()
            containsObject:CLExpectedEndpointName]
        && self.localReturnDestination;

    if (!endpointsReady) {
        if (self.simulatorAutoRestoreAttempts < 10) {
            self.simulatorAutoRestoreAttempts++;

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(1.0 * NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    [self restorePersistedSimulatorAutoDevices];
                }
            );
        }

        [self updateSimulatorCompactStatus];
        return;
    }

    self.simulatorAutoRestoreAttempts = 0;

    NSUInteger restored = 0;

    for (NSMutableDictionary *device in self.simulatorDevices ?: @[]) {
        NSString *deviceID = device[@"id"] ?: @"";

        if (![wanted containsObject:deviceID])
            continue;

        if (![device[@"enabled"] boolValue])
            continue;

        if (![[device[@"signal_type"] lowercaseString]
                isEqualToString:@"program_change"])
            continue;

        if (self.simulatorTasks[deviceID].running)
            continue;

        NSTask *task =
            [self launchSimulatorDevice:device
                              transport:@"iac"
                               endpoint:CLLocalReturnEndpointName
                                  delay:80];

        if (task.running)
            restored++;
    }

    [self rebuildSimulatorDeviceRows];
    [self updateSimulatorCompactStatus];

    CLAppendDiagnostic(
        @"simulator-auto-restored",
        [NSString stringWithFormat:
            @"restored=%lu wanted=%lu",
            (unsigned long)restored,
            (unsigned long)wanted.count]
    );
}

- (void)startIntegratedSimulator:(id)sender {
    (void)sender;
    [self stopIntegratedSimulator:nil];
    NSString *transport, *endpoint; NSInteger delay;
    if (![self simulatorTransport:&transport endpoint:&endpoint delay:&delay]) return;
    for (NSMutableDictionary *device in self.simulatorDevices) {
        if ([device[@"enabled"] boolValue] &&
            [[device[@"signal_type"] lowercaseString]
                isEqualToString:@"program_change"]) {

            NSTask *task =
                [self launchSimulatorDevice:device
                                  transport:transport
                                   endpoint:endpoint
                                      delay:delay];

            if (task.running)
                CLPersistSimulatorAutoDeviceID(device[@"id"], YES);
        }
    }
    [self rebuildSimulatorDeviceRows];
    CLAppendDiagnostic(@"integrated-simulator-started", [NSString stringWithFormat:@"devices=%lu mode=%@ endpoint=%@ delay=%ld", (unsigned long)self.simulatorTasks.count, transport, endpoint, (long)delay]);
}

- (void)stopIntegratedSimulator:(id)sender {
    (void)sender;
    NSArray *tasks = self.simulatorTasks.allValues.copy;
    [self.simulatorTasks removeAllObjects];
    [self.simulatorOutputBuffers removeAllObjects];
    for (NSTask *task in tasks)
        if (task.running) [task terminate];

    if (sender != nil)
        CLClearPersistedSimulatorAutoDeviceIDs();

    [self rebuildSimulatorDeviceRows];
    [self updateSimulatorCompactStatus];
    [self appendSimulatorJournalKind:@"SYS" message:@"Tout arrêter"];
    CLAppendDiagnostic(@"integrated-simulator-stopped", @"all local simulator tasks stopped");
}

- (void)toggleSimulatorDeviceEnabled:(NSButton *)sender {
    NSMutableDictionary *device = [self simulatorDeviceForID:sender.identifier];
    device[@"enabled"] = @(sender.state == NSControlStateValueOn); [self persistSimulatorDevices];
    if (![device[@"enabled"] boolValue]) [self stopSimulatorDeviceID:device[@"id"]];
}

- (void)toggleSimulatorDeviceRunning:(NSButton *)sender {
    NSString *deviceID = sender.identifier; NSMutableDictionary *device = [self simulatorDeviceForID:deviceID];
    if (![[device[@"signal_type"] lowercaseString] isEqualToString:@"program_change"]) return;
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
}

#pragma mark - Device Profiles editor (configuration only)

- (NSButton *)deviceCheck:(NSString *)title frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.buttonType = NSButtonTypeSwitch; button.title = title;
    button.font = [NSFont systemFontOfSize:10]; return button;
}

- (void)openDevicesEditor:(id)sender {
    (void)sender;
    if (self.devicesWindow) {
        [self.devicesWindow makeKeyAndOrderFront:nil];
        return;
    }
    self.devicesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 690)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.devicesWindow.title = @"CL MIDI Network Manager · Appareils";
    self.devicesWindow.delegate = self;
    [self.devicesWindow center];
    NSView *content = self.devicesWindow.contentView; content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithRed:0.045 green:0.052 blue:0.066 alpha:1.0].CGColor;
    [content addSubview:[self label:@"APPAREILS DU SPECTACLE" frame:NSMakeRect(20, 650, 260, 24) size:17 bold:YES]];
    NSTextField *intro = [self label:@"Consoles et appareils MIDI suivis · production historique protégée" frame:NSMakeRect(270, 650, 420, 22) size:10 bold:NO]; intro.alignment = NSTextAlignmentRight; [content addSubview:intro];
    self.deviceProfileMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 604, 260, 32) pullsDown:NO]; self.deviceProfileMenu.target = self; self.deviceProfileMenu.action = @selector(deviceProfileChanged:); [content addSubview:self.deviceProfileMenu];
    [content addSubview:[self accentButton:@"+ Nouvel appareil" frame:NSMakeRect(292, 604, 122, 32) action:@selector(addDeviceProfile:) color:[NSColor colorWithRed:0.22 green:0.48 blue:0.68 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Retirer" frame:NSMakeRect(422, 604, 76, 32) action:@selector(deleteDeviceProfile:) color:[NSColor colorWithRed:0.56 green:0.24 blue:0.27 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Réinitialiser CL5 / QL1…" frame:NSMakeRect(506, 604, 104, 32) action:@selector(restoreDefaultDeviceProfiles:) color:[NSColor colorWithRed:0.31 green:0.30 blue:0.34 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Appliquer" frame:NSMakeRect(618, 604, 82, 32) action:@selector(saveDeviceProfiles:) color:[NSColor colorWithRed:0.12 green:0.52 blue:0.35 alpha:1.0]]];

    NSArray *labels = @[@"Nom dans le spectacle", @"Identifiant technique", @"Canal MIDI", @"Piste(s) / alias Ableton", @"Couleur"];
    NSArray *ys = @[@552, @508, @464, @420, @376];
    for (NSUInteger i = 0; i < labels.count; i++) [content addSubview:[self label:labels[i] frame:NSMakeRect(22, [ys[i] doubleValue] + 25, 250, 16) size:9 bold:YES]];
    self.deviceNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 548, 320, 28)]; [content addSubview:self.deviceNameField];
    self.deviceIDField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 504, 320, 28)]; self.deviceIDField.editable = NO; self.deviceIDField.textColor = NSColor.secondaryLabelColor; [content addSubview:self.deviceIDField];
    self.deviceChannelField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 100, 28)]; [content addSubview:self.deviceChannelField];
    [content addSubview:[self label:@"Signal MIDI" frame:NSMakeRect(140, 484, 120, 16) size:9 bold:YES]];
    self.deviceSignalMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 458, 190, 30) pullsDown:NO];
    [self.deviceSignalMenu addItemsWithTitles:@[@"Program Change", @"Control Change", @"Note"]];
    self.deviceSignalMenu.target = self;
    self.deviceSignalMenu.action = @selector(deviceSignalChanged:);
    [content addSubview:self.deviceSignalMenu];
    [content addSubview:[self label:@"Console · MIDI" frame:NSMakeRect(350, 462, 250, 22) size:9 bold:NO]];
    self.deviceAliasesField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 416, 680, 28)]; [content addSubview:self.deviceAliasesField];
    self.devicePaletteMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 372, 180, 30) pullsDown:NO]; [self.devicePaletteMenu addItemsWithTitles:@[@"Violet", @"Cyan", @"Bleu", @"Orange", @"Rose", @"Jaune", @"Rouge", @"Vert", @"Personnalisée"]]; self.devicePaletteMenu.target = self; self.devicePaletteMenu.action = @selector(devicePaletteChanged:); [content addSubview:self.devicePaletteMenu];
    [content addSubview:[self label:@"UTILISATION" frame:NSMakeRect(210, 400, 220, 13) size:8 bold:YES]];
    self.deviceEnabledCheck = [self deviceCheck:@"Utilisé" frame:NSMakeRect(210, 373, 74, 26)]; [content addSubview:self.deviceEnabledCheck];
    self.deviceShowCheck = [self deviceCheck:@"Show" frame:NSMakeRect(284, 373, 68, 26)]; [content addSubview:self.deviceShowCheck];
    self.deviceRemoteCheck = [self deviceCheck:@"Remote" frame:NSMakeRect(352, 373, 82, 26)]; [content addSubview:self.deviceRemoteCheck];
    self.deviceNetworkCheck = [self deviceCheck:@"Manager" frame:NSMakeRect(434, 373, 86, 26)]; [content addSubview:self.deviceNetworkCheck];
    [content addSubview:[self label:@"MIDI" frame:NSMakeRect(520, 400, 120, 13) size:8 bold:YES]];
    self.deviceTXCheck = [self deviceCheck:@"Envoi" frame:NSMakeRect(520, 373, 76, 26)]; [content addSubview:self.deviceTXCheck];
    self.deviceRXCheck = [self deviceCheck:@"Retour" frame:NSMakeRect(596, 373, 84, 26)]; [content addSubview:self.deviceRXCheck];

    self.deviceEnabledCheck.toolTip = @"Utiliser cet appareil dans CL MIDI Network Manager.";
    self.deviceShowCheck.toolTip = @"Afficher cet appareil dans CL Show Control.";
    self.deviceRemoteCheck.toolTip = @"Afficher cet appareil dans la télécommande.";
    self.deviceNetworkCheck.toolTip = @"Afficher cet appareil dans le Network Manager.";
    self.deviceTXCheck.toolTip = @"Autoriser l’envoi MIDI pour cet appareil.";
    self.deviceRXCheck.toolTip = @"Autoriser son retour MIDI. Utilisé + Retour sont requis pour apparaître dans le simulateur.";
    [content addSubview:[self label:@"Bibliothèque" frame:NSMakeRect(22, 345, 90, 16) size:9 bold:YES]];
    self.deviceLibraryField = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 337, 190, 28)]; [content addSubview:self.deviceLibraryField];
    self.deviceLibraryHint = [self label:@"ID utilisé par Program Change" frame:NSMakeRect(314, 340, 386, 20) size:9 bold:NO];
    self.deviceLibraryHint.textColor = NSColor.secondaryLabelColor; [content addSubview:self.deviceLibraryHint];
    self.deviceConfigStatus = [self label:@"" frame:NSMakeRect(20, 311, 680, 24) size:10 bold:YES]; [content addSubview:self.deviceConfigStatus];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(20, 304, 680, 1)]; separator.boxType = NSBoxSeparator; [content addSubview:separator];
    [content addSubview:[self label:@"TEST MIDI DE L’APPAREIL" frame:NSMakeRect(20, 286, 280, 22) size:14 bold:YES]];
    NSTextField *warning = [self label:@"Test isolé · aucun impact production" frame:NSMakeRect(430, 286, 270, 20) size:9 bold:NO]; warning.alignment = NSTextAlignmentRight; warning.textColor = NSColor.secondaryLabelColor; [content addSubview:warning];
    [content addSubview:[self label:@"Destination d’envoi" frame:NSMakeRect(20, 254, 180, 16) size:9 bold:YES]];
    [content addSubview:[self label:@"Source de retour" frame:NSMakeRect(260, 254, 180, 16) size:9 bold:YES]];
    self.deviceTestParameterLabel = [self label:@"Mémoire 1–128" frame:NSMakeRect(500, 254, 100, 16) size:9 bold:YES];
    [content addSubview:self.deviceTestParameterLabel];
    self.deviceTestValueLabel = [self label:@"Valeur 0–127" frame:NSMakeRect(605, 254, 95, 16) size:9 bold:YES];
    [content addSubview:self.deviceTestValueLabel];
    self.deviceTestDestinationMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 218, 220, 30) pullsDown:NO]; [content addSubview:self.deviceTestDestinationMenu];
    self.deviceTestSourceMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(260, 218, 220, 30) pullsDown:NO]; [content addSubview:self.deviceTestSourceMenu];
    self.deviceTestProgramField = [[NSTextField alloc] initWithFrame:NSMakeRect(500, 218, 90, 30)];
    self.deviceTestProgramField.alignment = NSTextAlignmentCenter;
    [content addSubview:self.deviceTestProgramField];
    self.deviceTestValueField = [[NSTextField alloc] initWithFrame:NSMakeRect(605, 218, 90, 30)];
    self.deviceTestValueField.alignment = NSTextAlignmentCenter;
    [content addSubview:self.deviceTestValueField];
    [content addSubview:[self accentButton:@"TEST ENVOI" frame:NSMakeRect(20, 166, 150, 34) action:@selector(sendIsolatedDeviceTestTX:) color:[NSColor colorWithRed:0.40 green:0.34 blue:0.70 alpha:1.0]]];
    [content addSubview:[self accentButton:@"ALLER-RETOUR" frame:NSMakeRect(180, 166, 210, 34) action:@selector(runIsolatedDeviceRoundTrip:) color:[NSColor colorWithRed:0.16 green:0.56 blue:0.36 alpha:1.0]]];
    [content addSubview:[self accentButton:@"ÉCOUTER RETOUR" frame:NSMakeRect(400, 166, 130, 34) action:@selector(startIsolatedDeviceTestRX:) color:[NSColor colorWithRed:0.22 green:0.48 blue:0.68 alpha:1.0]]];
    self.deviceTestResult = [self label:@"Aucun TEST TX/RX exécuté" frame:NSMakeRect(20, 88, 680, 42) size:13 bold:YES];
    self.deviceTestResult.maximumNumberOfLines = 2;
    self.deviceTestResult.textColor = [NSColor colorWithRed:0.36 green:0.82 blue:0.94 alpha:1.0];
    [content addSubview:self.deviceTestResult];

    [content addSubview:[self accentButton:@"Actualiser les ports" frame:NSMakeRect(390, 30, 145, 28) action:@selector(refreshIsolatedDeviceTestEndpoints:) color:[NSColor colorWithWhite:0.28 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Tous les ports MIDI…" frame:NSMakeRect(545, 30, 155, 28) action:@selector(showAllMidiEndpoints:) color:[NSColor colorWithWhite:0.22 alpha:1.0]]];
    NSString *loadError = nil;
    self.deviceProfiles = [self loadDeviceProfilesForEditor:&loadError];
    if (!self.deviceTestClient) MIDIClientCreate(CFSTR("CL Device Test Bench"), CLDeviceTestMIDINotify, (__bridge void *)self, &_deviceTestClient);
    [self refreshDeviceProfileMenuSelectingID:@"console_a"];
    [self refreshIsolatedDeviceTestEndpoints:nil];
    if (loadError.length) { self.deviceConfigStatus.stringValue = loadError; self.deviceConfigStatus.textColor = NSColor.systemRedColor; }
    [self.devicesWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
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
        NSString *title = device[@"display_name"] ?: @"Appareil sans nom";
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
    NSString *signalType = [device[@"signal_type"] lowercaseString] ?: @"program_change";
    NSString *signalTitle = [signalType isEqualToString:@"control_change"] ? @"Control Change" :
                            [signalType isEqualToString:@"note"] ? @"Note" : @"Program Change";
    [self.deviceSignalMenu selectItemWithTitle:signalTitle];
    BOOL historicalConsole = [device[@"id"] isEqualToString:@"console_a"] || [device[@"id"] isEqualToString:@"console_b"];
    self.deviceSignalMenu.enabled = !historicalConsole;
    id rawLibrary = device[@"library"];
    self.deviceLibraryField.stringValue = [rawLibrary isKindOfClass:NSString.class] ? rawLibrary : @"";
    self.deviceLibraryField.enabled = !historicalConsole && [signalType isEqualToString:@"program_change"];
    self.deviceLibraryHint.stringValue = historicalConsole
        ? @"Bibliothèque historique verrouillée"
        : ([signalType isEqualToString:@"program_change"]
            ? @"ID utilisé par Program Change"
            : @"Non utilisée pour CC/Note · valeur conservée");
    self.deviceAliasesField.stringValue = [device[@"ableton_track_aliases"] componentsJoinedByString:@", "] ?: @"";
    self.deviceEnabledCheck.state = [device[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSDictionary *visibility = device[@"visibility"];
    self.deviceShowCheck.state = [visibility[@"show_control"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceRemoteCheck.state = [visibility[@"remote"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceNetworkCheck.state = [visibility[@"network_manager"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceTXCheck.state = [device[@"tx"][@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.deviceRXCheck.state = [device[@"rx"][@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    NSArray *colors = @[device[@"palette"][@"base"] ?: @"", device[@"palette"][@"accent"] ?: @""];
    NSString *presetName = @"Personnalisée";
    for (NSString *name in [self devicePalettePresets]) if ([[self devicePalettePresets][name] isEqual:colors]) { presetName = name; break; }
    [self.devicePaletteMenu selectItemWithTitle:presetName];
    [self updateDeviceTestFieldsForSelectedProfile];
    BOOL used = [device[@"enabled"] boolValue];
    BOOL returnEnabled = [device[@"rx"][@"enabled"] boolValue];
    if (!used) {
        self.deviceConfigStatus.textColor = NSColor.secondaryLabelColor;
        self.deviceConfigStatus.stringValue =
            [NSString stringWithFormat:@"Hors service · %@ Ch.%@ · n’apparaît pas dans le simulateur",
             signalTitle, self.deviceChannelField.stringValue];
    } else if (!returnEnabled) {
        self.deviceConfigStatus.textColor = NSColor.systemOrangeColor;
        self.deviceConfigStatus.stringValue =
            [NSString stringWithFormat:@"Utilisé · %@ Ch.%@ · Retour MIDI désactivé",
             signalTitle, self.deviceChannelField.stringValue];
    } else {
        self.deviceConfigStatus.textColor =
            [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0];
        self.deviceConfigStatus.stringValue =
            [NSString stringWithFormat:@"✓ Utilisé · %@ Ch.%@ · visible dans le simulateur",
             signalTitle, self.deviceChannelField.stringValue];
    }
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
    NSRegularExpression *library = [NSRegularExpression regularExpressionWithPattern:@"^[a-z0-9][a-z0-9_-]{0,63}$" options:0 error:nil];
    for (NSDictionary *device in self.deviceProfiles) {
        NSString *deviceID = device[@"id"], *name = [device[@"display_name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!deviceID.length || [ids containsObject:deviceID]) return @"Chaque ID interne doit être unique";
        [ids addObject:deviceID]; hasA |= [deviceID isEqualToString:@"console_a"]; hasB |= [deviceID isEqualToString:@"console_b"];
        if (!name.length) return [NSString stringWithFormat:@"%@ : nom affiché obligatoire", deviceID];
        NSInteger channel = [device[@"midi_channel"] integerValue];
        if (channel < 1 || channel > 16) return [NSString stringWithFormat:@"%@ : canal MIDI attendu entre 1 et 16", name];
        if ([deviceID isEqualToString:@"console_a"] && channel != 1) return @"CL5 historique doit rester sur le canal MIDI 1";
        if ([deviceID isEqualToString:@"console_b"] && channel != 2) return @"QL1 historique doit rester sur le canal MIDI 2";
        id rawLibrary = device[@"library"];
        NSString *libraryID = [rawLibrary isKindOfClass:NSString.class] ? rawLibrary : @"";
        if (libraryID.length && [library numberOfMatchesInString:libraryID options:0 range:NSMakeRange(0, libraryID.length)] != 1)
            return [NSString stringWithFormat:@"%@ : bibliothèque invalide (minuscules, chiffres, _ ou -, 64 caractères max)", name];
        if ([deviceID isEqualToString:@"console_a"] && ![libraryID isEqualToString:@"cl5"]) return @"CL5 historique doit conserver la bibliothèque cl5";
        if ([deviceID isEqualToString:@"console_b"] && ![libraryID isEqualToString:@"ql1"]) return @"QL1 historique doit conserver la bibliothèque ql1";
        NSDictionary *palette = device[@"palette"];
        for (NSString *key in @[@"base", @"accent"]) if ([color numberOfMatchesInString:palette[key] ?: @"" options:0 range:NSMakeRange(0, [palette[key] length]) ] != 1) return [NSString stringWithFormat:@"%@ : palette invalide", name];
        if ([device[@"enabled"] boolValue]) {
            if (![[device[@"protocol"] lowercaseString] isEqualToString:@"midi"])
                return [NSString stringWithFormat:@"%@ : protocole non pris en charge", name];

            NSString *signalType = [device[@"signal_type"] lowercaseString] ?: @"";
            NSSet *supportedSignalTypes = [NSSet setWithObjects:@"program_change", @"control_change", @"note", nil];
            if (![supportedSignalTypes containsObject:signalType])
                return [NSString stringWithFormat:@"%@ : type de signal MIDI non pris en charge", name];

            if ([signalType isEqualToString:@"program_change"] &&
                ![device[@"ableton_track_aliases"] count])
                return [NSString stringWithFormat:@"%@ : au moins un alias Ableton est requis", name];

            NSNumber *channelNumber = @(channel);
            if ([enabledChannels containsObject:channelNumber])
                return [NSString stringWithFormat:@"%@ : collision de canal MIDI", name];
            [enabledChannels addObject:channelNumber];
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
    NSString *signalTitle = self.deviceSignalMenu.titleOfSelectedItem ?: @"Program Change";
    NSString *signalType = [signalTitle isEqualToString:@"Control Change"] ? @"control_change" :
                           [signalTitle isEqualToString:@"Note"] ? @"note" : @"program_change";
    NSString *deviceID = device[@"id"] ?: @"";
    if ([deviceID isEqualToString:@"console_a"] || [deviceID isEqualToString:@"console_b"]) signalType = @"program_change";
    device[@"signal_type"] = signalType;
    NSString *libraryID = [[self.deviceLibraryField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([deviceID isEqualToString:@"console_a"]) libraryID = @"cl5";
    else if ([deviceID isEqualToString:@"console_b"]) libraryID = @"ql1";
    device[@"library"] = libraryID.length ? libraryID : NSNull.null;
    device[@"visibility"] = @{ @"show_control": @(self.deviceShowCheck.state == NSControlStateValueOn), @"remote": @(self.deviceRemoteCheck.state == NSControlStateValueOn), @"network_manager": @(self.deviceNetworkCheck.state == NSControlStateValueOn) };
    device[@"tx"] = @{ @"enabled": @(self.deviceTXCheck.state == NSControlStateValueOn) };
    device[@"rx"] = @{ @"enabled": @(self.deviceRXCheck.state == NSControlStateValueOn) };
    NSString *preset = self.devicePaletteMenu.titleOfSelectedItem;
    NSArray *colors = [self devicePalettePresets][preset];
    if (colors) device[@"palette"] = @{ @"base": colors[0], @"accent": colors[1] };
    NSString *error = [self validateDeviceProfiles];
    if (error.length) { self.deviceConfigStatus.stringValue = error; self.deviceConfigStatus.textColor = NSColor.systemRedColor; return NO; }
    return YES;
}

- (void)saveDeviceProfiles:(id)sender {
    NSButton *applyButton = [sender isKindOfClass:NSButton.class] ? (NSButton *)sender : nil;
    if (applyButton) applyButton.title = @"Application…";
    if (![self commitVisibleDeviceFields]) {
        if (applyButton) applyButton.title = @"Appliquer";
        return;
    }
    NSDictionary *payload = @{ @"schema_version": @(CLDeviceSchemaVersion), @"profile_id": @"default", @"profile_name": @"Configuration personnalisée", @"devices": self.deviceProfiles };
    NSError *error = nil; NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    NSString *path = CLDeviceConfigurationPath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
    BOOL saved = data && [data writeToFile:path options:NSDataWritingAtomic error:&error];
    [self refreshDeviceProfileMenuSelectingID:[self selectedDeviceProfile][@"id"]];
    if (saved) {
        [self refreshProfileDrivenViews];
    }
    self.deviceConfigStatus.textColor = saved ? [NSColor colorWithRed:0.45 green:0.88 blue:0.60 alpha:1.0] : NSColor.systemRedColor;
    self.deviceConfigStatus.stringValue = saved
        ? @"✓ Configuration appliquée · vues et simulateur actualisés"
        : [NSString stringWithFormat:@"Application impossible : %@", error.localizedDescription ?: @"erreur"];

    if (saved) {
        self.deviceConfigStatus.alphaValue = 0.30;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.20;
            self.deviceConfigStatus.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }

    if (applyButton) {
        applyButton.title = saved ? @"✓ Appliqué" : @"Appliquer";
        if (saved) {
            __weak NSButton *weakButton = applyButton;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if ([weakButton.title isEqualToString:@"✓ Appliqué"])
                    weakButton.title = @"Appliquer";
            });
        }
    }
}

- (void)restoreDefaultDeviceProfiles:(id)sender {
    (void)sender; NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Restaurer CL5 / QL1 par défaut ?"; alert.informativeText = @"Les réglages MIDI système, RTP et bibliothèques CLF ne seront pas modifiés."; [alert addButtonWithTitle:@"Restaurer"]; [alert addButtonWithTitle:@"Annuler"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.deviceProfiles = [NSMutableArray array]; for (NSDictionary *device in [self defaultDeviceConfigurationPayload][@"devices"]) [self.deviceProfiles addObject:[device mutableCopy]];
    [self refreshDeviceProfileMenuSelectingID:@"console_a"];
    [self refreshProfileDrivenViews];
    self.deviceConfigStatus.stringValue = @"Réglages CL5 / QL1 prêts · Appliquer pour confirmer";
}

- (void)addDeviceProfile:(id)sender {
    (void)sender; NSUInteger index = 3; NSMutableSet *ids = [NSMutableSet set]; NSMutableIndexSet *usedChannels = [NSMutableIndexSet indexSet]; for (NSDictionary *device in self.deviceProfiles) { [ids addObject:device[@"id"]]; NSInteger channel = [device[@"midi_channel"] integerValue]; if (channel >= 1 && channel <= 16) [usedChannels addIndex:(NSUInteger)channel]; } while ([ids containsObject:[NSString stringWithFormat:@"device_%lu", (unsigned long)index]]) index++;
    NSString *deviceID = [NSString stringWithFormat:@"device_%lu", (unsigned long)index];
    NSUInteger midiChannel = 1; while (midiChannel <= 16 && [usedChannels containsIndex:midiChannel]) midiChannel++; if (midiChannel > 16) midiChannel = 1;
    NSMutableDictionary *device = [@{ @"id": deviceID, @"display_name": @"Nouveau device", @"enabled": @NO, @"device_type": @"console", @"protocol": @"midi", @"signal_type": @"program_change", @"midi_channel": @(midiChannel), @"ableton_track_aliases": @[@"NOUVEAU DEVICE PROGRAM"], @"palette": @{ @"base": @"#79B8FF", @"accent": @"#397FD1" }, @"library": NSNull.null, @"legacy_key": NSNull.null, @"visibility": @{ @"show_control": @YES, @"remote": @YES, @"network_manager": @YES }, @"tx": @{ @"enabled": @YES }, @"rx": @{ @"enabled": @YES } } mutableCopy];
    [self.deviceProfiles addObject:device]; [self refreshDeviceProfileMenuSelectingID:deviceID]; self.deviceConfigStatus.stringValue = @"Nouvel appareil créé · hors service jusqu’à activation · Appliquer pour confirmer";
}

- (void)deleteDeviceProfile:(id)sender {
    (void)sender; NSMutableDictionary *device = [self selectedDeviceProfile]; NSString *deviceID = device[@"id"];
    if ([deviceID isEqualToString:@"console_a"] || [deviceID isEqualToString:@"console_b"]) { self.deviceConfigStatus.stringValue = @"Les devices historiques peuvent être désactivés, pas supprimés"; return; }
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = [NSString stringWithFormat:@"Supprimer %@ ?", device[@"display_name"]]; [alert addButtonWithTitle:@"Supprimer"]; [alert addButtonWithTitle:@"Annuler"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self.deviceProfiles removeObject:device];
        [self refreshDeviceProfileMenuSelectingID:@"console_a"];
        [self refreshProfileDrivenViews];
    }
}

- (void)deviceProfileChanged:(id)sender { (void)sender; [self populateDeviceEditorFields]; }

- (void)deviceSignalChanged:(id)sender {
    (void)sender;
    NSMutableDictionary *device = [self selectedDeviceProfile];
    if (!device) return;

    NSString *title = self.deviceSignalMenu.titleOfSelectedItem ?: @"Program Change";
    NSString *signalType =
        [title isEqualToString:@"Control Change"] ? @"control_change" :
        [title isEqualToString:@"Note"] ? @"note" : @"program_change";

    NSString *deviceID = device[@"id"] ?: @"";
    if ([deviceID isEqualToString:@"console_a"] || [deviceID isEqualToString:@"console_b"]) {
        signalType = @"program_change";
        title = @"Program Change";
        [self.deviceSignalMenu selectItemWithTitle:title];
    }

    device[@"signal_type"] = signalType;
    [self refreshProfileDrivenViews];
    BOOL libraryAvailable = [signalType isEqualToString:@"program_change"];
    self.deviceLibraryField.enabled = libraryAvailable;
    self.deviceLibraryHint.stringValue = libraryAvailable
        ? @"ID utilisé par Program Change"
        : @"Non utilisée pour CC/Note · valeur conservée";
    [self updateDeviceTestFieldsForSelectedProfile];

    self.deviceConfigStatus.stringValue =
        [NSString stringWithFormat:@"MIDI · %@ · canal %@ · ID non modifiable",
         title, self.deviceChannelField.stringValue ?: @""];
}

- (void)updateDeviceTestFieldsForSelectedProfile {
    NSString *title = self.deviceSignalMenu.titleOfSelectedItem ?: @"Program Change";
    BOOL isCC = [title isEqualToString:@"Control Change"];
    BOOL isNote = [title isEqualToString:@"Note"];

    self.deviceTestValueField.hidden = !(isCC || isNote);
    self.deviceTestValueLabel.hidden = !(isCC || isNote);

    if (isCC) {
        self.deviceTestParameterLabel.stringValue = @"CC 0–127";
        self.deviceTestValueLabel.stringValue = @"Valeur 0–127";
        self.deviceTestProgramField.stringValue = @"1";
        self.deviceTestValueField.stringValue = @"127";
    } else if (isNote) {
        self.deviceTestParameterLabel.stringValue = @"Note 0–127";
        self.deviceTestValueLabel.stringValue = @"Vélocité 0–127";
        self.deviceTestProgramField.stringValue = @"60";
        self.deviceTestValueField.stringValue = @"100";
    } else {
        self.deviceTestParameterLabel.stringValue = @"Mémoire 1–128";
        self.deviceTestProgramField.stringValue = @"81";
        self.deviceTestValueField.stringValue = @"";
    }
}

- (NSString *)hexStringFromColor:(NSColor *)color {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return @"#808080";

    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    [rgb getRed:&red green:&green blue:&blue alpha:&alpha];

    return [NSString stringWithFormat:@"#%02X%02X%02X",
        (int)lround(red * 255.0),
        (int)lround(green * 255.0),
        (int)lround(blue * 255.0)];
}

- (void)deviceCustomColorChanged:(id)sender {
    NSColorPanel *panel = [sender isKindOfClass:NSColorPanel.class]
        ? (NSColorPanel *)sender
        : NSColorPanel.sharedColorPanel;

    NSMutableDictionary *device = [self selectedDeviceProfile];
    if (!device) return;

    NSColor *baseColor = [panel.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!baseColor) return;

    NSColor *accentColor =
        [baseColor blendedColorWithFraction:0.28 ofColor:NSColor.blackColor];

    device[@"palette"] = @{
        @"base": [self hexStringFromColor:baseColor],
        @"accent": [self hexStringFromColor:accentColor]
    };

    [self.devicePaletteMenu selectItemWithTitle:@"Personnalisée"];
    self.deviceConfigStatus.textColor = NSColor.secondaryLabelColor;
    self.deviceConfigStatus.stringValue = @"Couleur personnalisée sélectionnée · Appliquer pour confirmer";
}

- (void)devicePaletteChanged:(id)sender {
    (void)sender;

    NSString *preset = self.devicePaletteMenu.titleOfSelectedItem;
    if (![preset isEqualToString:@"Personnalisée"]) {
        self.deviceConfigStatus.textColor = NSColor.secondaryLabelColor;
        self.deviceConfigStatus.stringValue = @"Couleur d’identité sélectionnée · Appliquer pour confirmer";
        return;
    }

    NSDictionary *device = [self selectedDeviceProfile];
    NSDictionary *palette = [device[@"palette"] isKindOfClass:NSDictionary.class]
        ? device[@"palette"] : @{};

    NSColor *initialColor =
        [self deviceColorFromHex:palette[@"base"]
                        fallback:[NSColor colorWithRed:0.47 green:0.72 blue:1.0 alpha:1.0]];

    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.showsAlpha = NO;
    panel.continuous = YES;
    panel.target = self;
    panel.action = @selector(deviceCustomColorChanged:);
    panel.color = initialColor;
    [panel orderFront:nil];

    self.deviceConfigStatus.textColor = NSColor.secondaryLabelColor;
    self.deviceConfigStatus.stringValue = @"Choisissez la couleur d’identité";
}

- (void)refreshIsolatedDeviceTestEndpoints:(id)sender {
    (void)sender;
    NSString *selectedDestination = self.deviceTestDestinationMenu.titleOfSelectedItem;
    NSString *selectedSource = self.deviceTestSourceMenu.titleOfSelectedItem;
    [self.deviceTestDestinationMenu removeAllItems];
    [self.deviceTestSourceMenu removeAllItems];
    NSArray<NSString *> *destinations = EndpointNames(NO);
    for (NSString *name in destinations) if (!CLIsProtectedDeviceTestEndpoint(name)) [self.deviceTestDestinationMenu addItemWithTitle:name];
    NSArray<NSString *> *sources = EndpointNames(YES);
    for (NSString *name in sources) if (!CLIsProtectedDeviceTestEndpoint(name)) [self.deviceTestSourceMenu addItemWithTitle:name];
    if (!self.deviceTestDestinationMenu.numberOfItems) [self.deviceTestDestinationMenu addItemWithTitle:@"Aucune destination de test sûre"];
    if (!self.deviceTestSourceMenu.numberOfItems) [self.deviceTestSourceMenu addItemWithTitle:@"Aucune source de test sûre"];
    if (selectedDestination.length && [self.deviceTestDestinationMenu itemWithTitle:selectedDestination]) [self.deviceTestDestinationMenu selectItemWithTitle:selectedDestination];
    if (selectedSource.length && [self.deviceTestSourceMenu itemWithTitle:selectedSource]) [self.deviceTestSourceMenu selectItemWithTitle:selectedSource];
}

- (void)showAllMidiEndpoints:(id)sender {
    (void)sender; NSArray<NSDictionary *> *rows = CLAllMIDIEndpointInventory();
    NSMutableString *report = [NSMutableString stringWithFormat:@"VÉRITÉ COREMIDI BRUTE · %lu endpoint(s)\nDécouverte complète ; la protection ci-dessous contrôle seulement l’usage dans le Test Bench.\n\n", (unsigned long)rows.count];
    for (NSDictionary *row in rows) {
        [report appendFormat:@"%@\n  %@ · %@ · %@ · ID %@\n  device: %@ · entity: %@\n  fabricant: %@ · modèle: %@ · driver: %@\n  %@%@\n\n",
            row[@"name"], row[@"direction"], row[@"transport"], [row[@"online"] boolValue] ? @"online" : @"offline", row[@"unique_id"],
            [row[@"device"] length] ? row[@"device"] : @"—", [row[@"entity"] length] ? row[@"entity"] : @"—",
            [row[@"manufacturer"] length] ? row[@"manufacturer"] : @"—", [row[@"model"] length] ? row[@"model"] : @"—", [row[@"driver"] length] ? row[@"driver"] : @"—",
            [row[@"protected"] boolValue] ? @"PROTÉGÉ · " : @"DISPONIBLE POUR TEST · ", [row[@"protected"] boolValue] ? row[@"reason"] : @"aucune restriction métier"];
    }
    if (!rows.count) [report appendString:@"Aucun endpoint exposé par CoreMIDI.\n"];
    self.midiInventoryWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 620) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
    self.midiInventoryWindow.title = @"Tous les ports MIDI";
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.midiInventoryWindow.contentView.bounds]; scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.hasVerticalScroller = YES;
    NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds]; textView.editable = NO; textView.selectable = YES; textView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; textView.string = report;
    scroll.documentView = textView; [self.midiInventoryWindow.contentView addSubview:scroll]; [self.midiInventoryWindow center]; [self.midiInventoryWindow makeKeyAndOrderFront:nil];
}

- (void)startIsolatedDeviceTestRX:(id)sender {
    (void)sender; NSDictionary *device = [self selectedDeviceProfile]; NSString *name = self.deviceTestSourceMenu.titleOfSelectedItem;
    [NSData.data writeToFile:CLDeviceTestRXDiagnosticPath atomically:YES];
    CLDeviceTestRXDiagnostic(@"RX_ARM_REQUEST", [NSString stringWithFormat:@"selected_source=%@", name ?: @"<nil>"]);
    if (![device[@"rx"][@"enabled"] boolValue]) {
        if (self.deviceTestSource && self.deviceTestInputPort) MIDIPortDisconnectSource(self.deviceTestInputPort, self.deviceTestSource);
        self.deviceTestSource = 0; self.deviceTestSourceName = nil; self.deviceTestRunningStatus = 0; self.deviceTestHasDataByte = NO; self.deviceTestDataByte = 0; self.deviceTestResult.stringValue = @"TEST RX refusé · RX désactivé pour cet appareil"; return;
    }
    if (CLIsProtectedDeviceTestEndpoint(name) || [name hasPrefix:@"Aucune"]) {
        if (self.deviceTestSource && self.deviceTestInputPort) MIDIPortDisconnectSource(self.deviceTestInputPort, self.deviceTestSource);
        self.deviceTestSource = 0; self.deviceTestSourceName = nil; self.deviceTestRunningStatus = 0; self.deviceTestHasDataByte = NO; self.deviceTestDataByte = 0; self.deviceTestResult.stringValue = @"TEST RX refusé · endpoint protégé ou absent"; return;
    }
    OSStatus clientStatus = self.deviceTestClient ? noErr : MIDIClientCreate(CFSTR("CL Device Test Bench"), CLDeviceTestMIDINotify, (__bridge void *)self, &_deviceTestClient);
    OSStatus portStatus = (clientStatus == noErr && !self.deviceTestInputPort)
        ? MIDIInputPortCreate(self.deviceTestClient, CFSTR("Isolated test RX"), CLIsolatedDeviceTestRead, (__bridge void *)self, &_deviceTestInputPort)
        : (self.deviceTestInputPort ? noErr : clientStatus);
    if (clientStatus != noErr || portStatus != noErr) {
        self.deviceTestSource = 0; self.deviceTestSourceName = nil; self.deviceTestRunningStatus = 0; self.deviceTestHasDataByte = NO; self.deviceTestDataByte = 0;
        self.deviceTestResult.stringValue = [NSString stringWithFormat:@"TEST RX impossible · client=%d port=%d", (int)clientStatus, (int)portStatus]; return;
    }
    if (self.deviceTestSource) MIDIPortDisconnectSource(self.deviceTestInputPort, self.deviceTestSource);
    self.deviceTestSource = 0; self.deviceTestSourceName = nil; self.deviceTestRunningStatus = 0; self.deviceTestHasDataByte = NO; self.deviceTestDataByte = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) { MIDIEndpointRef source = MIDIGetSource(index); if ([EndpointName(source) isEqualToString:name]) { self.deviceTestSource = source; break; } }
    OSStatus status = self.deviceTestSource ? MIDIPortConnectSource(self.deviceTestInputPort, self.deviceTestSource, (void *)(uintptr_t)self.deviceTestSource) : -1;
    if (status == noErr) self.deviceTestSourceName = name;
    else self.deviceTestSource = 0;
    CLDeviceTestRXDiagnostic(@"RX_ARM_RESULT", [NSString stringWithFormat:@"status=%d source_ref=%u source_unique_id=%d source_name=%@ input_port=%u", (int)status, (unsigned)self.deviceTestSource, (int)CLEndpointUniqueID(self.deviceTestSource), name ?: @"<nil>", (unsigned)self.deviceTestInputPort]);
    self.deviceTestResult.stringValue = status == noErr ? [NSString stringWithFormat:@"TEST RX · entrée isolée connectée à %@", name] : [NSString stringWithFormat:@"TEST RX impossible · connexion=%d", (int)status];
}

- (void)sendIsolatedDeviceTestTX:(id)sender {
    (void)sender;
    NSDictionary *device = [self selectedDeviceProfile];
    NSString *destinationName = self.deviceTestDestinationMenu.titleOfSelectedItem;
    NSInteger channel = [device[@"midi_channel"] integerValue];

    NSString *signalTitle = self.deviceSignalMenu.titleOfSelectedItem ?: @"Program Change";
    NSString *signalType =
        [signalTitle isEqualToString:@"Control Change"] ? @"control_change" :
        [signalTitle isEqualToString:@"Note"] ? @"note" : @"program_change";

    NSInteger data1Input = self.deviceTestProgramField.integerValue;
    NSInteger data2Input = self.deviceTestValueField.integerValue;

    if (![device[@"tx"][@"enabled"] boolValue]) {
        self.deviceTestSent = nil;
        self.deviceTestResult.stringValue = @"TEST TX refusé · TX désactivé pour cet appareil";
        return;
    }

    BOOL valid = channel >= 1 && channel <= 16;
    if ([signalType isEqualToString:@"program_change"])
        valid &= data1Input >= 1 && data1Input <= 128;
    else
        valid &= data1Input >= 0 && data1Input <= 127 && data2Input >= 0 && data2Input <= 127;

    if (CLIsProtectedDeviceTestEndpoint(destinationName) ||
        [destinationName hasPrefix:@"Aucune"] || !valid) {
        self.deviceTestSent = nil;
        self.deviceTestResult.stringValue = @"TEST TX refusé · destination protégée ou valeur invalide";
        return;
    }

    MIDIEndpointRef destination = 0;
    for (ItemCount index = 0; index < MIDIGetNumberOfDestinations(); index++) {
        MIDIEndpointRef item = MIDIGetDestination(index);
        if ([EndpointName(item) isEqualToString:destinationName]) {
            destination = item;
            break;
        }
    }

    if (!self.deviceTestClient)
        MIDIClientCreate(CFSTR("CL Device Test Bench"), CLDeviceTestMIDINotify,
                         (__bridge void *)self, &_deviceTestClient);
    if (!self.deviceTestOutputPort)
        MIDIOutputPortCreate(self.deviceTestClient, CFSTR("Isolated test TX"),
                             &_deviceTestOutputPort);

    UInt8 bytes[3] = {0, 0, 0};
    UInt16 length = 0;
    UInt8 data1 = 0;
    NSInteger data2 = -1;
    NSString *sentType = signalType;

    if ([signalType isEqualToString:@"control_change"]) {
        data1 = (UInt8)data1Input;
        data2 = data2Input;
        bytes[0] = (UInt8)(0xB0 | ((channel - 1) & 0x0F));
        bytes[1] = data1;
        bytes[2] = (UInt8)data2;
        length = 3;
    } else if ([signalType isEqualToString:@"note"]) {
        data1 = (UInt8)data1Input;
        data2 = data2Input;
        sentType = data2Input == 0 ? @"note_off" : @"note_on";
        bytes[0] = (UInt8)(0x90 | ((channel - 1) & 0x0F));
        bytes[1] = data1;
        bytes[2] = (UInt8)data2;
        length = 3;
    } else {
        data1 = (UInt8)(data1Input - 1);
        bytes[0] = (UInt8)(0xC0 | ((channel - 1) & 0x0F));
        bytes[1] = data1;
        length = 2;
    }

    Byte buffer[128];
    MIDIPacketList *packets = (MIDIPacketList *)buffer;
    MIDIPacket *packet = MIDIPacketListInit(packets);
    packet = MIDIPacketListAdd(packets, sizeof(buffer), packet, 0, length, bytes);

    OSStatus status = destination && packet
        ? MIDISend(self.deviceTestOutputPort, destination, packets)
        : -1;

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    self.deviceTestSent = status == noErr ? @{
        @"device_id": device[@"id"] ?: @"",
        @"type": sentType,
        @"channel": @(channel),
        @"data1": @(data1),
        @"data2": @(data2),
        @"timestamp": @(now),
        @"destination": destinationName ?: @""
    } : nil;

    if (status != noErr) {
        self.deviceTestResult.stringValue = @"TEST TX échec CoreMIDI";
    } else if ([signalType isEqualToString:@"program_change"]) {
        self.deviceTestResult.stringValue =
            [NSString stringWithFormat:@"TEST TX · Program Change · Ch.%ld · mémoire %ld · %@",
             (long)channel, (long)data1Input, destinationName];
    } else if ([signalType isEqualToString:@"control_change"]) {
        self.deviceTestResult.stringValue =
            [NSString stringWithFormat:@"TEST TX · CC · Ch.%ld · CC %ld · valeur %ld · %@",
             (long)channel, (long)data1Input, (long)data2Input, destinationName];
    } else {
        self.deviceTestResult.stringValue =
            [NSString stringWithFormat:@"TEST TX · Note · Ch.%ld · note %ld · vélocité %ld · %@",
             (long)channel, (long)data1Input, (long)data2Input, destinationName];
    }
}

- (void)runIsolatedDeviceRoundTrip:(id)sender {
    (void)sender; self.deviceRoundTripPending = NO; self.deviceRoundTripGeneration++; self.deviceTestReceived = nil; self.deviceTestSent = nil;
    [self startIsolatedDeviceTestRX:nil];
    if (!self.deviceTestSource) { self.deviceTestResult.stringValue = [@"ROUND TRIP TEST FAIL · " stringByAppendingString:self.deviceTestResult.stringValue]; return; }
    self.deviceRoundTripPending = YES; NSUInteger generation = self.deviceRoundTripGeneration;
    [self sendIsolatedDeviceTestTX:nil];
    if (!self.deviceTestSent) { self.deviceRoundTripPending = NO; self.deviceTestResult.stringValue = [@"ROUND TRIP TEST FAIL · " stringByAppendingString:self.deviceTestResult.stringValue]; return; }
    self.deviceTestResult.stringValue = @"ROUND TRIP TEST EN ATTENTE · émission réussie · timeout 2,0 s";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.deviceRoundTripPending && self.deviceRoundTripGeneration == generation) {
            self.deviceRoundTripPending = NO; self.deviceTestResult.stringValue = @"ROUND TRIP TEST FAIL · timeout 2,0 s · aucun retour correspondant";
        }
    });
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender == self.devicesWindow || sender == self.simulatorWindow) {
        [sender orderOut:nil];
        [self.window makeKeyAndOrderFront:nil];
        return NO;
    }
    return YES;
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
    [self.modeSyncTimer invalidate];
    [self.serviceBrowser stop];
    [self.agentServiceBrowser stop];
    if (self.guardianTask.running) [self.guardianTask terminate];
    if (self.returnMonitorSource && self.returnMonitorInputPort) {
        MIDIPortDisconnectSource(self.returnMonitorInputPort, self.returnMonitorSource);
    }
    if (self.returnMonitorInputPort) MIDIPortDispose(self.returnMonitorInputPort);
    if (self.returnMonitorClient) MIDIClientDispose(self.returnMonitorClient);
    if (self.simulatorMidiOutputPort) MIDIPortDispose(self.simulatorMidiOutputPort);
    if (self.simulatorMidiClient) MIDIClientDispose(self.simulatorMidiClient);
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

// Actual CFMessagePort round trips; no application startup, production files or MIDI.
#define main CLDashboardApplicationMain
#import "../../tools/cl_midi_network/CLMIDINetworkDashboard.m"
#undef main
#import <objc/runtime.h>

// Keep all preference writes in memory, including the real AUTO persistence helpers.
@interface CLMemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation CLMemoryDefaults
- (NSArray *)arrayForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
static CLMemoryDefaults *testDefaults;
static id CLTestStandardDefaults(id object, SEL selector) { return testDefaults; }

@interface CLControlTestTask : NSTask
@property BOOL testRunning;
@property BOOL terminationRequested;
@end
@implementation CLControlTestTask
- (BOOL)isRunning { return self.testRunning; }
- (void)terminate { self.terminationRequested = YES; }
@end

@interface CLControlTestOwner : CLNetworkDelegate
@property NSUInteger launches;
@property NSDictionary *snapshot;
@end
@implementation CLControlTestOwner
- (void)startSimulatorDevice:(NSMutableDictionary *)device {
    if (self.simulatorTasks[device[@"id"]].running) return;
    CLControlTestTask *task = [CLControlTestTask new]; task.testRunning = YES;
    self.simulatorTasks[device[@"id"]] = task; self.launches++;
}
- (void)rebuildSimulatorDeviceRows { }
- (void)writeConsoleReturnState {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSDictionary *device in self.simulatorDevices)
        snapshot[device[@"id"]] = @{@"running": @(self.simulatorTasks[device[@"id"]].running)};
    self.snapshot = snapshot;
}
@end

@interface CLControlTestClient : CLNetworkDelegate
@property CLControlTestOwner *testOwner;
@property BOOL lastCommandFailed;
@end
@implementation CLControlTestClient
- (void)loadPublishedConsoleReturnState { self.publishedSimulatorStates = self.testOwner.snapshot; }
- (void)rebuildSimulatorDeviceRows { }
- (void)showSimulatorOperatorMessage:(NSString *)message error:(BOOL)error { self.lastCommandFailed = error; }
@end
@interface CLControlTestButton : NSObject
@property NSString *identifier;
@end
@implementation CLControlTestButton
@end

static NSDictionary *CLCommand(NSString *action, NSString *deviceID) {
    NSMutableDictionary *request = [@{@"service": CLSimulatorControlService,
        @"action": action, @"deadline": @(NSDate.date.timeIntervalSince1970 + 2.0)} mutableCopy];
    if (deviceID) request[@"device_id"] = deviceID;
    return request;
}
static void CLPumpUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    NSCAssert(done(), @"Timed out waiting for control reply");
}
// The client sends from another thread so the main run loop can service the owner.
static NSDictionary *CLRoundTrip(NSString *port, NSDictionary *request) {
    __block BOOL done = NO; __block NSDictionary *reply;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSDictionary *result = CLSimulatorControlRequest(port, request);
        dispatch_async(dispatch_get_main_queue(), ^{ reply = result; done = YES; });
    });
    CLPumpUntil(^BOOL{ return done; });
    return reply;
}

static void CLClientAction(void (^action)(void)) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        action();
        dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    });
    CLPumpUntil(^BOOL{ return done; });
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--port-client") == 0) {
            NSDictionary *reply = CLSimulatorControlRequest([NSString stringWithUTF8String:argv[2]], CLCommand(@"auto", nil));
            return [reply[@"ok"] boolValue] ? 0 : 1;
        }
        testDefaults = [CLMemoryDefaults new]; testDefaults.values = [NSMutableDictionary dictionary];
        method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)),
                                 (IMP)CLTestStandardDefaults);
        CLControlTestOwner *owner = [CLControlTestOwner new];
        owner.ownsPassiveReturnMonitor = YES; owner.backgroundMonitorOnly = YES;
        owner.simulatorTasks = [NSMutableDictionary dictionary];
        owner.simulatorOutputBuffers = [NSMutableDictionary dictionary];
        owner.simulatorDevices = [@[
            [@{@"id": @"cl5", @"name": @"CL5", @"channel": @1, @"enabled": @YES, @"signal_type": @"program_change"} mutableCopy],
            [@{@"id": @"ql1", @"name": @"QL1", @"channel": @2, @"enabled": @YES, @"signal_type": @"program_change"} mutableCopy],
            [@{@"id": @"empty", @"test_only": @YES, @"enabled": @YES, @"signal_type": @"program_change"} mutableCopy],
            [@{@"id": @"cc", @"enabled": @YES, @"signal_type": @"control_change"} mutableCopy]
        ] mutableCopy];
        [owner startSimulatorControlServer];
        NSCAssert(owner.simulatorControlPort != NULL, @"Owner opens control port");
        NSString *port = owner.simulatorControlPortName;
        NSCAssert([CLRoundTrip(port, CLCommand(@"ping", nil))[@"ok"] boolValue], @"Owner responds to ping");
        // A separate client process proves the channel crosses instance boundaries.
        NSTask *wireClient = [NSTask new];
        wireClient.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments.firstObject];
        wireClient.arguments = @[@"--port-client", port];
        NSError *launchError;
        NSCAssert([wireClient launchAndReturnError:&launchError], @"Test client starts: %@", launchError);
        CLPumpUntil(^BOOL{ return !wireClient.running; });
        NSCAssert(wireClient.terminationStatus == 0, @"Cross-process AUTO accepted");
        NSCAssert([CLRoundTrip(port, CLCommand(@"auto", nil))[@"ok"] boolValue], @"Global AUTO accepted");
        NSCAssert(owner.simulatorTasks.count == 2 && owner.launches == 2, @"Only one CL5 and QL1");
        NSCAssert(CLPersistedSimulatorAutoDeviceIDs().count == 2, @"Owner persists AUTO");
        NSCAssert([owner.snapshot[@"cl5"][@"running"] boolValue] && [owner.snapshot[@"ql1"][@"running"] boolValue], @"Canonical snapshot active");
        CLRoundTrip(port, CLCommand(@"auto", nil));
        NSCAssert(owner.launches == 2, @"Repeated AUTO does not duplicate tasks");
        NSCAssert(![CLRoundTrip(port, CLCommand(@"stop", @"missing"))[@"ok"] boolValue], @"Unknown ID rejected");
        NSCAssert(![CLRoundTrip(port, CLCommand(@"auto", @"cc"))[@"ok"] boolValue], @"Non-PC rejected");
        NSCAssert(![CLRoundTrip(port, @{@"service": CLSimulatorControlService, @"action": @"stop", @"deadline": @0})[@"ok"] boolValue], @"Expired command rejected");
        NSCAssert(![CLRoundTrip(port, CLCommand(@"launch-arbitrary-process", nil))[@"ok"] boolValue], @"Unknown action rejected");
        NSCAssert(![CLRoundTrip(port, @{@"service": @"other", @"action": @"stop"})[@"ok"] boolValue], @"Wrong service rejected");
        NSCAssert(owner.launches == 2 && owner.simulatorTasks.count == 2, @"Rejected requests do not mutate state");

        CLControlTestTask *cl5 = (id)owner.simulatorTasks[@"cl5"];
        CLControlTestTask *ql1 = (id)owner.simulatorTasks[@"ql1"];
        NSCAssert([CLRoundTrip(port, CLCommand(@"stop", nil))[@"ok"] boolValue], @"Global STOP accepted");
        NSCAssert(cl5.terminationRequested && ql1.terminationRequested, @"Owner terminates its tasks");
        NSCAssert(CLPersistedSimulatorAutoDeviceIDs().count == 0, @"STOP clears AUTO intent");
        NSCAssert(![owner.snapshot[@"cl5"][@"running"] boolValue] && ![owner.snapshot[@"ql1"][@"running"] boolValue], @"Canonical snapshot stopped");
        CLRoundTrip(port, CLCommand(@"auto", nil));
        NSCAssert(owner.launches == 2, @"AUTO waits for terminating tasks");
        // A second STOP cancels an AUTO already waiting for termination.
        CLRoundTrip(port, CLCommand(@"stop", nil));
        cl5.testRunning = NO; ql1.testRunning = NO;
        NSDate *drain = [NSDate dateWithTimeIntervalSinceNow:0.2];
        while (drain.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        NSCAssert(owner.launches == 2, @"Deferred AUTO cancelled by STOP");
        CLRoundTrip(port, CLCommand(@"auto", nil));
        NSCAssert(owner.simulatorTasks.count == 2 && owner.launches == 4, @"AUTO relaunches exactly one pair");
        NSCAssert([owner.simulatorDevices[0][@"channel"] integerValue] == 1 && [owner.simulatorDevices[1][@"channel"] integerValue] == 2, @"Channels unchanged");
        CLRoundTrip(port, CLCommand(@"stop", @"cl5"));
        NSCAssert(![CLPersistedSimulatorAutoDeviceIDs() containsObject:@"cl5"] && [CLPersistedSimulatorAutoDeviceIDs() containsObject:@"ql1"], @"Per-line STOP preserves other line");
        ((CLControlTestTask *)owner.simulatorCommandRetiringTasks[@"cl5"]).testRunning = NO;
        CLRoundTrip(port, CLCommand(@"auto", @"cl5"));
        NSCAssert(owner.simulatorTasks.count == 2, @"Per-line AUTO restored");

        CLControlTestClient *client = [CLControlTestClient new];
        client.testOwner = owner;
        client.simulatorDevices = owner.simulatorDevices;
        client.simulatorTasks = [NSMutableDictionary dictionary];
        client.publishedSimulatorStates = owner.snapshot;
        client.publishedSimulatorControlAvailable = YES; client.publishedSimulatorControlPortName = port;
        NSCAssert([client canControlSimulators], @"Reachable client enabled");
        [client startSimulatorControlServer];
        NSCAssert(client.simulatorControlPort == NULL, @"Client cannot own a port");
        NSCAssert(![[client handleSimulatorControlRequest:CLCommand(@"stop", nil)][@"ok"] boolValue], @"Client cannot execute owner requests");
        [client stopIntegratedSimulator:nil]; // Client teardown must send nothing.
        NSCAssert(owner.simulatorTasks.count == 2, @"Closing secondary keeps owner tasks");
        NSCAssert([client launchSimulatorDevice:nil transport:nil endpoint:nil delay:0] == nil, @"Client cannot launch locally");
        // Exercise the actual secondary UI action routing as well as the wire protocol.
        CLControlTestTask *clientCL5 = (id)owner.simulatorTasks[@"cl5"];
        CLControlTestTask *clientQL1 = (id)owner.simulatorTasks[@"ql1"];
        CLClientAction(^{ [client stopIntegratedSimulator:@YES]; });
        NSCAssert(!client.lastCommandFailed && owner.simulatorTasks.count == 0, @"Client global STOP forwarded");
        NSCAssert(![client simulatorIsRunningForDeviceID:@"cl5"], @"Client displays stopped canonical snapshot");
        clientCL5.testRunning = NO; clientQL1.testRunning = NO;
        CLClientAction(^{ [client autoIntegratedSimulators:@YES]; });
        NSCAssert(!client.lastCommandFailed && owner.simulatorTasks.count == 2, @"Client global AUTO forwarded");
        NSCAssert([client activeSimulatorCount] == 2 && client.simulatorTasks.count == 0, @"Client reads canonical state and owns no tasks");
        CLControlTestButton *button = [CLControlTestButton new]; button.identifier = @"cl5";
        clientCL5 = (id)owner.simulatorTasks[@"cl5"];
        CLClientAction(^{ [client toggleSimulatorDeviceRunning:(id)button]; });
        NSCAssert(![client simulatorIsRunningForDeviceID:@"cl5"] && [client simulatorIsRunningForDeviceID:@"ql1"], @"Client per-line STOP forwarded");
        clientCL5.testRunning = NO;
        CLClientAction(^{ [client toggleSimulatorDeviceRunning:(id)button]; });
        NSCAssert([client activeSimulatorCount] == 2 && client.simulatorTasks.count == 0, @"Client per-line AUTO forwarded");
        [client stopIntegratedSimulator:nil];
        NSCAssert(owner.simulatorTasks.count == 2, @"Client teardown after controls preserves pair");
        [owner stopSimulatorControlServer];
        NSCAssert(CLRoundTrip(port, CLCommand(@"ping", nil)) == nil, @"Port disappears on owner shutdown");
        CLClientAction(^{ [client stopIntegratedSimulator:@YES]; });
        NSCAssert(client.lastCommandFailed && owner.simulatorTasks.count == 2, @"Failed IPC never falls back to local control");
        NSCAssert(![client canControlSimulators], @"Disconnected client disabled");
        owner.lifecycleStopping = YES;
        NSCAssert(![[owner handleSimulatorControlRequest:CLCommand(@"auto", nil)][@"ok"] boolValue], @"Shutdown refuses commands");
        puts("PASS: real local IPC, owner-only control, AUTO persistence, drain and teardown");
    }
    return 0;
}

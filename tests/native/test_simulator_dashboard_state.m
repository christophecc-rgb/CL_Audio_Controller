// Exercise the dashboard's actual ownership branch without launching an app or MIDI.
#define main CLDashboardApplicationMain
#import "../../tools/cl_midi_network/CLMIDINetworkDashboard.m"
#undef main

@interface CLTestRunningTask : NSTask
@end
@implementation CLTestRunningTask
- (BOOL)isRunning { return YES; }
@end

int main(void) {
    @autoreleasepool {
        CLNetworkDelegate *dashboard = [CLNetworkDelegate new];
        dashboard.simulatorTasks = [NSMutableDictionary dictionary];
        dashboard.publishedSimulatorStates = @{
            @"cl5": @{@"running": @YES, @"channel": @1, @"pid": @101},
            @"ql1": @{@"running": @YES, @"channel": @2, @"pid": @102}
        };
        NSCAssert([dashboard activeSimulatorCount] == 2, @"Secondary uses canonical count");
        NSCAssert([dashboard simulatorIsRunningForDeviceID:@"cl5"], @"CL5 published active");
        NSCAssert([dashboard simulatorIsRunningForDeviceID:@"ql1"], @"QL1 published active");
        NSCAssert(![dashboard simulatorIsRunningForDeviceID:@"missing"], @"Missing device stopped");
        NSCAssert([dashboard launchSimulatorDevice:nil transport:nil endpoint:nil delay:0] == nil,
                  @"Secondary cannot launch");
        [dashboard startIntegratedSimulator:nil];
        [dashboard stopIntegratedSimulator:nil];
        [dashboard restorePersistedSimulatorAutoDevices];
        [dashboard reconcilePersistedSimulatorAutoDevicesAfterModeChange];
        NSCAssert(dashboard.simulatorTasks.count == 0, @"No secondary tasks");
        dashboard.publishedSimulatorStates = @{};
        NSCAssert([dashboard activeSimulatorCount] == 0, @"Cleared publication clears count");
        dashboard.simulatorTasks[@"local"] = [CLTestRunningTask new];
        NSCAssert([dashboard activeSimulatorCount] == 0, @"Secondary ignores local dictionary");
        dashboard.ownsPassiveReturnMonitor = YES;
        NSCAssert([dashboard activeSimulatorCount] == 1, @"Owner uses local tasks");
        NSCAssert([dashboard simulatorIsRunningForDeviceID:@"local"], @"Owner local task active");
        NSCAssert(![dashboard simulatorIsRunningForDeviceID:@"cl5"], @"Owner ignores publication");
        puts("PASS: dashboard simulator ownership and canonical state");
    }
    return 0;
}

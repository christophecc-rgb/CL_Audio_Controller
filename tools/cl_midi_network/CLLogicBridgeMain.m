#import "CLMIDIFramework.h"
#import "CLLogicBridge.h"

static void RunDemo(CLLogicBridge *bridge)
{
    [bridge receiveCommand:[[CLPlayCommand alloc] init]];
    [bridge receiveCommand:[[CLPlayCommand alloc] init]];
    [bridge receiveCommand:[[CLStopCommand alloc] init]];
    [bridge receiveCommand:[[CLRecordCommand alloc] init]];
    [bridge receiveCommand:[[CLPauseCommand alloc] init]];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        id<CLLogicTransportAdapter> adapter = [CLSimulatedLogicTransportAdapter new];
        CLLogicBridge *bridge = [[CLLogicBridge alloc] initWithTransportAdapter:adapter];
        if (argc == 2 && strcmp(argv[1], "--demo") == 0)
        {
            RunDemo(bridge);
            CLSimulatedLogicTransportAdapter *simulatedAdapter =
                (CLSimulatedLogicTransportAdapter *)adapter;
            printf("ADAPTER INVOCATIONS %lu\n", (unsigned long)simulatedAdapter.invocationCount);
            return 0;
        }

        CLMIDICore *core = [CLMIDICore new];
        core.commandReceiver = bridge;
        if (![core startMonitoring]) return 1;
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}

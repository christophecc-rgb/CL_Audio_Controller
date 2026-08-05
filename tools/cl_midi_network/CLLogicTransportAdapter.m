#import "CLLogicTransportAdapter.h"

@implementation CLSimulatedLogicTransportAdapter

- (void)applyTransportAction:(CLTransportAction)action
                       state:(CLLogicTransportStateValue)state
{
    _invocationCount += 1;
    _lastAction = action;
    _lastState = state;
}

@end

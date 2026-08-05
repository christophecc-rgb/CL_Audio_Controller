#import "CLLogicTransportState.h"

NSString *CLLogicTransportStateName(CLLogicTransportStateValue state)
{
    switch (state)
    {
        case CLLogicTransportStateStopped: return @"Stopped";
        case CLLogicTransportStatePlaying: return @"Playing";
        case CLLogicTransportStateRecording: return @"Recording";
        case CLLogicTransportStatePaused: return @"Paused";
    }
}

@implementation CLLogicTransportState

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _value = CLLogicTransportStateStopped;
        _name = CLLogicTransportStateName(_value);
    }
    return self;
}

- (BOOL)applyTransportAction:(CLTransportAction)action
{
    CLLogicTransportStateValue nextState = _value;
    switch (action)
    {
        case CLTransportActionPlay: nextState = CLLogicTransportStatePlaying; break;
        case CLTransportActionStop: nextState = CLLogicTransportStateStopped; break;
        case CLTransportActionRecord: nextState = CLLogicTransportStateRecording; break;
        case CLTransportActionPause: nextState = CLLogicTransportStatePaused; break;
        case CLTransportActionClock: return NO;
    }

    if (nextState == _value)
    {
        return NO;
    }
    _value = nextState;
    _name = CLLogicTransportStateName(_value);
    return YES;
}

@end

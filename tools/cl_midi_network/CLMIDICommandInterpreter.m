#import "CLMIDICommandInterpreter.h"
#import "CLCommand.h"
#import "CLMIDIEvent.h"

@interface CLMIDICommandInterpreter ()
{
    NSUInteger _bankMSB[16];
    NSUInteger _bankLSB[16];
}
@end

@implementation CLMIDICommandInterpreter

- (NSArray<CLCommand *> *)commandsForEvent:(CLMIDIEvent *)event
{
    switch (event.type)
    {
        case CLMIDIEventTypeStart:
        case CLMIDIEventTypeContinue:
            return @[[[CLPlayCommand alloc] init]];
        case CLMIDIEventTypeStop:
            return @[[[CLStopCommand alloc] init]];
        case CLMIDIEventTypeTimingClock:
            return @[[[CLTransportCommand alloc] initWithAction:CLTransportActionClock]];
        case CLMIDIEventTypeProgramChange:
            if (event.program != nil)
            {
                return @[[[CLProgramSelectCommand alloc]
                    initWithProgram:event.program.unsignedIntegerValue
                           channel:event.channel]];
            }
            break;
        case CLMIDIEventTypeControlChange:
            if ((event.controller.unsignedIntegerValue == 0 ||
                 event.controller.unsignedIntegerValue == 32) &&
                event.value != nil)
            {
                NSUInteger channelIndex = event.channel.unsignedIntegerValue - 1;
                if (event.controller.unsignedIntegerValue == 0)
                {
                    _bankMSB[channelIndex] = event.value.unsignedIntegerValue;
                }
                else
                {
                    _bankLSB[channelIndex] = event.value.unsignedIntegerValue;
                }
                return @[[[CLBankCommand alloc]
                    initWithMSB:_bankMSB[channelIndex]
                             LSB:_bankLSB[channelIndex]
                         channel:event.channel]];
            }
            break;
        default:
            break;
    }
    return @[];
}

@end

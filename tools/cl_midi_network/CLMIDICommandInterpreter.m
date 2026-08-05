#import "CLMIDICommandInterpreter.h"
#import "CLCommand.h"
#import "CLMIDIEvent.h"

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
                return @[[[CLBankCommand alloc]
                    initWithBank:event.value.unsignedIntegerValue
                         channel:event.channel]];
            }
            break;
        default:
            break;
    }
    return @[];
}

@end

#import <Foundation/Foundation.h>
#import "CLCommand.h"
#import "CLMIDICommandInterpreter.h"
#import "CLMIDIEvent.h"
#import "CLMIDIPacket.h"

static CLMIDIEvent *Event(const UInt8 *bytes, NSUInteger length)
{
    CLMIDIPacket *packet = [[CLMIDIPacket alloc] initWithBytes:bytes
                                                       length:length
                                                    timestamp:1
                                                   sourceName:@"Test"];
    return [[CLMIDIEvent alloc] initWithPacket:packet];
}

static CLCommand *FirstCommand(CLMIDICommandInterpreter *interpreter,
                               const UInt8 *bytes,
                               NSUInteger length)
{
    return [interpreter commandsForEvent:Event(bytes, length)].firstObject;
}

int main(void)
{
    @autoreleasepool
    {
        CLMIDICommandInterpreter *interpreter = [CLMIDICommandInterpreter new];

        const UInt8 start[] = {0xFA};
        CLCommand *play = FirstCommand(interpreter, start, sizeof(start));
        NSCAssert([play isKindOfClass:CLPlayCommand.class], @"Start must produce Play");
        NSCAssert(play.kind == CLCommandKindTransport, @"Play must be a transport command");

        const UInt8 stop[] = {0xFC};
        NSCAssert([FirstCommand(interpreter, stop, sizeof(stop)) isKindOfClass:CLStopCommand.class],
                  @"Stop must produce Stop");

        const UInt8 clock[] = {0xF8};
        CLTransportCommand *tick = (CLTransportCommand *)FirstCommand(interpreter, clock, sizeof(clock));
        NSCAssert(tick.action == CLTransportActionClock, @"Clock must produce a transport tick");

        const UInt8 programChange[] = {0xCF, 42};
        CLProgramSelectCommand *program = (CLProgramSelectCommand *)FirstCommand(
            interpreter, programChange, sizeof(programChange));
        NSCAssert([program isKindOfClass:CLProgramSelectCommand.class], @"Expected Program Select");
        NSCAssert(program.program == 42, @"Expected program 42");
        NSCAssert(program.channel.unsignedIntegerValue == 16, @"Expected channel 16");

        const UInt8 bankSelect[] = {0xB0, 0, 7};
        CLBankCommand *bank = (CLBankCommand *)FirstCommand(interpreter, bankSelect, sizeof(bankSelect));
        NSCAssert([bank isKindOfClass:CLBankCommand.class], @"Expected Bank");
        NSCAssert(bank.bank == 7, @"Expected bank 7");

        const UInt8 note[] = {0x90, 60, 100};
        NSCAssert([interpreter commandsForEvent:Event(note, sizeof(note))].count == 0,
                  @"Standard MIDI notes have no protocol-independent command mapping");

        CLSceneRecallCommand *scene = [[CLSceneRecallCommand alloc] initWithScene:18];
        CLJogCommand *jog = [[CLJogCommand alloc] initWithDelta:-1.5];
        CLPauseCommand *pause = [[CLPauseCommand alloc] init];
        CLRecordCommand *record = [[CLRecordCommand alloc] init];
        NSCAssert(scene.scene == 18 && scene.kind == CLCommandKindSceneRecall,
                  @"Scene Recall must be constructible by Yamaha or OSC interpreters");
        NSCAssert(jog.delta == -1.5 && jog.kind == CLCommandKindJog,
                  @"Jog must preserve its protocol-independent delta");
        NSCAssert(pause.action == CLTransportActionPause, @"Expected Pause");
        NSCAssert(record.action == CLTransportActionRecord, @"Expected Record");
        NSCAssert([CLCommand instancesRespondToSelector:@selector(name)],
                  @"Commands expose a stable receiver-facing API");
    }
    return 0;
}

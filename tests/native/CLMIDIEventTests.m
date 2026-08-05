#import <Foundation/Foundation.h>
#import "CLMIDIEvent.h"
#import "CLMIDIPacket.h"

static CLMIDIEvent *Event(const UInt8 *bytes, NSUInteger length)
{
    CLMIDIPacket *packet = [[CLMIDIPacket alloc] initWithBytes:bytes
                                                       length:length
                                                    timestamp:123
                                                   sourceName:@"Test Source"];
    CLMIDIEvent *event = [[CLMIDIEvent alloc] initWithPacket:packet];
    NSCAssert(event.packet == packet, @"The raw packet must be preserved");
    NSCAssert(event.protocol == CLMIDIEventProtocolMIDI1ByteStream, @"Unexpected protocol");
    return event;
}

int main(void)
{
    @autoreleasepool
    {
        const UInt8 noteOn[] = {0x92, 60, 127};
        CLMIDIEvent *note = Event(noteOn, sizeof(noteOn));
        NSCAssert(note.type == CLMIDIEventTypeNoteOn, @"Expected Note On");
        NSCAssert(note.channel.unsignedIntegerValue == 3, @"Expected channel 3");
        NSCAssert(note.note.unsignedIntegerValue == 60, @"Expected note 60");
        NSCAssert(note.velocity.unsignedIntegerValue == 127, @"Expected velocity 127");

        const UInt8 zeroVelocity[] = {0x90, 64, 0};
        NSCAssert(Event(zeroVelocity, sizeof(zeroVelocity)).type == CLMIDIEventTypeNoteOff,
                  @"A zero-velocity Note On is semantically Note Off");

        const UInt8 controlChange[] = {0xBF, 7, 100};
        CLMIDIEvent *control = Event(controlChange, sizeof(controlChange));
        NSCAssert(control.type == CLMIDIEventTypeControlChange, @"Expected Control Change");
        NSCAssert(control.channel.unsignedIntegerValue == 16, @"Expected channel 16");
        NSCAssert(control.controller.unsignedIntegerValue == 7, @"Expected controller 7");
        NSCAssert(control.value.unsignedIntegerValue == 100, @"Expected value 100");

        const UInt8 programChange[] = {0xCF, 42};
        CLMIDIEvent *program = Event(programChange, sizeof(programChange));
        NSCAssert(program.type == CLMIDIEventTypeProgramChange, @"Expected Program Change");
        NSCAssert(program.program.unsignedIntegerValue == 42, @"Expected program 42");

        const UInt8 centeredPitchBend[] = {0xE0, 0x00, 0x40};
        CLMIDIEvent *pitch = Event(centeredPitchBend, sizeof(centeredPitchBend));
        NSCAssert(pitch.type == CLMIDIEventTypePitchBend, @"Expected Pitch Bend");
        NSCAssert(pitch.pitchBendRaw.unsignedIntegerValue == 8192, @"Expected raw center");
        NSCAssert(pitch.pitchBend.integerValue == 0, @"Expected signed center");

        const UInt8 clock[] = {0xF8};
        NSCAssert(Event(clock, sizeof(clock)).type == CLMIDIEventTypeTimingClock,
                  @"Expected Timing Clock");

        const UInt8 sysEx[] = {0xF0, 0x43, 0x10, 0xF7};
        NSCAssert(Event(sysEx, sizeof(sysEx)).type == CLMIDIEventTypeSystemExclusive,
                  @"Expected System Exclusive");

        const UInt8 songPosition[] = {0xF2, 0x01, 0x02};
        CLMIDIEvent *position = Event(songPosition, sizeof(songPosition));
        NSCAssert(position.songPosition.unsignedIntegerValue == 257,
                  @"Expected 14-bit song position");
    }
    return 0;
}

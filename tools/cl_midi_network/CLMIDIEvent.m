#import "CLMIDIEvent.h"
#import "CLMIDIPacket.h"

@implementation CLMIDIEvent

- (instancetype)initWithPacket:(CLMIDIPacket *)packet
{
    self = [super init];
    if (self)
    {
        _packet = packet;
        _protocol = CLMIDIEventProtocolMIDI1ByteStream;
        [self parseData:packet.data];
        _typeName = [self.class nameForType:_type];
    }
    return self;
}

- (void)parseData:(NSData *)data
{
    if (data.length == 0)
    {
        _type = CLMIDIEventTypeUnknown;
        return;
    }

    const UInt8 *bytes = data.bytes;
    _statusByte = bytes[0];
    if (_statusByte < 0x80)
    {
        _type = CLMIDIEventTypeData;
        return;
    }

    if (_statusByte < 0xF0)
    {
        _channel = @((_statusByte & 0x0F) + 1);
        [self parseChannelMessage:bytes length:data.length];
        return;
    }

    [self parseSystemMessage:bytes length:data.length];
}

- (void)parseChannelMessage:(const UInt8 *)bytes length:(NSUInteger)length
{
    switch (_statusByte & 0xF0)
    {
        case 0x80:
            _type = CLMIDIEventTypeNoteOff;
            if (length >= 2) _note = @(bytes[1]);
            if (length >= 3) _velocity = @(bytes[2]);
            break;
        case 0x90:
            _type = length >= 3 && bytes[2] == 0
                ? CLMIDIEventTypeNoteOff
                : CLMIDIEventTypeNoteOn;
            if (length >= 2) _note = @(bytes[1]);
            if (length >= 3) _velocity = @(bytes[2]);
            break;
        case 0xA0:
            _type = CLMIDIEventTypePolyphonicKeyPressure;
            if (length >= 2) _note = @(bytes[1]);
            if (length >= 3) _pressure = @(bytes[2]);
            break;
        case 0xB0:
            _type = CLMIDIEventTypeControlChange;
            if (length >= 2) _controller = @(bytes[1]);
            if (length >= 3) _value = @(bytes[2]);
            break;
        case 0xC0:
            _type = CLMIDIEventTypeProgramChange;
            if (length >= 2) _program = @(bytes[1]);
            break;
        case 0xD0:
            _type = CLMIDIEventTypeChannelPressure;
            if (length >= 2) _pressure = @(bytes[1]);
            break;
        case 0xE0:
            _type = CLMIDIEventTypePitchBend;
            if (length >= 3)
            {
                NSUInteger rawValue = bytes[1] | ((NSUInteger)bytes[2] << 7);
                _pitchBendRaw = @(rawValue);
                _pitchBend = @((NSInteger)rawValue - 8192);
            }
            break;
        default:
            _type = CLMIDIEventTypeUnknown;
            break;
    }
}

- (void)parseSystemMessage:(const UInt8 *)bytes length:(NSUInteger)length
{
    switch (_statusByte)
    {
        case 0xF0: _type = CLMIDIEventTypeSystemExclusive; break;
        case 0xF1:
            _type = CLMIDIEventTypeMIDITimeCodeQuarterFrame;
            if (length >= 2) _value = @(bytes[1]);
            break;
        case 0xF2:
            _type = CLMIDIEventTypeSongPositionPointer;
            if (length >= 3) _songPosition = @(bytes[1] | ((NSUInteger)bytes[2] << 7));
            break;
        case 0xF3:
            _type = CLMIDIEventTypeSongSelect;
            if (length >= 2) _song = @(bytes[1]);
            break;
        case 0xF6: _type = CLMIDIEventTypeTuneRequest; break;
        case 0xF8: _type = CLMIDIEventTypeTimingClock; break;
        case 0xFA: _type = CLMIDIEventTypeStart; break;
        case 0xFB: _type = CLMIDIEventTypeContinue; break;
        case 0xFC: _type = CLMIDIEventTypeStop; break;
        case 0xFE: _type = CLMIDIEventTypeActiveSensing; break;
        case 0xFF: _type = CLMIDIEventTypeSystemReset; break;
        default: _type = CLMIDIEventTypeUnknown; break;
    }
}

+ (NSString *)nameForType:(CLMIDIEventType)type
{
    switch (type)
    {
        case CLMIDIEventTypeData: return @"Data/Running Status";
        case CLMIDIEventTypeNoteOff: return @"Note Off";
        case CLMIDIEventTypeNoteOn: return @"Note On";
        case CLMIDIEventTypePolyphonicKeyPressure: return @"Polyphonic Key Pressure";
        case CLMIDIEventTypeControlChange: return @"Control Change";
        case CLMIDIEventTypeProgramChange: return @"Program Change";
        case CLMIDIEventTypeChannelPressure: return @"Channel Pressure";
        case CLMIDIEventTypePitchBend: return @"Pitch Bend";
        case CLMIDIEventTypeSystemExclusive: return @"System Exclusive";
        case CLMIDIEventTypeMIDITimeCodeQuarterFrame: return @"MIDI Time Code Quarter Frame";
        case CLMIDIEventTypeSongPositionPointer: return @"Song Position Pointer";
        case CLMIDIEventTypeSongSelect: return @"Song Select";
        case CLMIDIEventTypeTuneRequest: return @"Tune Request";
        case CLMIDIEventTypeTimingClock: return @"Timing Clock";
        case CLMIDIEventTypeStart: return @"Start";
        case CLMIDIEventTypeContinue: return @"Continue";
        case CLMIDIEventTypeStop: return @"Stop";
        case CLMIDIEventTypeActiveSensing: return @"Active Sensing";
        case CLMIDIEventTypeSystemReset: return @"System Reset";
        case CLMIDIEventTypeUnknown: return @"Unknown";
    }
}

@end

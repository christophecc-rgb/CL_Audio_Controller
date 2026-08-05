#import "CLMIDIPacket.h"

@implementation CLMIDIPacket

- (instancetype)initWithBytes:(const UInt8 *)bytes
                       length:(NSUInteger)length
                    timestamp:(MIDITimeStamp)timestamp
                   sourceName:(NSString *)sourceName
{
    self = [super init];
    if (self)
    {
        _data = bytes != NULL && length > 0
            ? [NSData dataWithBytes:bytes length:length]
            : [NSData data];
        _timestamp = timestamp;
        _sourceName = sourceName.length > 0 ? [sourceName copy] : @"<unknown>";
        _hexString = [self.class hexStringForData:_data];
        _messageType = [self.class messageTypeForData:_data];
        _channel = [self.class channelForData:_data];
    }
    return self;
}

+ (NSString *)hexStringForData:(NSData *)data
{
    const UInt8 *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 3];
    for (NSUInteger index = 0; index < data.length; index++)
    {
        [hex appendFormat:index == 0 ? @"%02X" : @" %02X", bytes[index]];
    }
    return hex;
}

+ (NSString *)messageTypeForData:(NSData *)data
{
    if (data.length == 0)
    {
        return @"Empty";
    }

    const UInt8 status = ((const UInt8 *)data.bytes)[0];
    if (status < 0x80)
    {
        return @"Data/Running Status";
    }

    switch (status & 0xF0)
    {
        case 0x80: return @"Note Off";
        case 0x90: return @"Note On";
        case 0xA0: return @"Polyphonic Key Pressure";
        case 0xB0: return @"Control Change";
        case 0xC0: return @"Program Change";
        case 0xD0: return @"Channel Pressure";
        case 0xE0: return @"Pitch Bend";
        case 0xF0:
            switch (status)
            {
                case 0xF0: return @"System Exclusive";
                case 0xF1: return @"MIDI Time Code Quarter Frame";
                case 0xF2: return @"Song Position Pointer";
                case 0xF3: return @"Song Select";
                case 0xF6: return @"Tune Request";
                case 0xF7: return @"End of System Exclusive";
                case 0xF8: return @"Timing Clock";
                case 0xFA: return @"Start";
                case 0xFB: return @"Continue";
                case 0xFC: return @"Stop";
                case 0xFE: return @"Active Sensing";
                case 0xFF: return @"System Reset";
                default: return @"System Message";
            }
    }

    return @"Unknown";
}

+ (NSNumber *)channelForData:(NSData *)data
{
    if (data.length == 0)
    {
        return nil;
    }

    const UInt8 status = ((const UInt8 *)data.bytes)[0];
    if (status < 0x80 || status >= 0xF0)
    {
        return nil;
    }
    return @((status & 0x0F) + 1);
}

@end

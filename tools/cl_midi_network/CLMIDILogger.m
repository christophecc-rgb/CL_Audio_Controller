#import "CLMIDILogger.h"
#import "CLMIDIPacket.h"

@implementation CLMIDILogger

- (void)logPacket:(CLMIDIPacket *)packet
{
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObjects:
        [NSString stringWithFormat:@"RX [%@]", packet.sourceName],
        packet.messageType,
        nil];

    if (packet.channel != nil)
    {
        [lines addObject:[NSString stringWithFormat:@"Channel %@", packet.channel]];
    }

    const UInt8 *bytes = packet.data.bytes;
    if ([packet.messageType isEqualToString:@"Program Change"] && packet.data.length >= 2)
    {
        [lines addObject:[NSString stringWithFormat:@"Program %u", bytes[1]]];
    }

    [lines addObject:@""];
    [lines addObject:packet.hexString];
    NSLog(@"\n%@", [lines componentsJoinedByString:@"\n"]);
}

@end

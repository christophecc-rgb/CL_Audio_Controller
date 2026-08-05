#import "CLMIDILogger.h"
#import "CLMIDIEvent.h"
#import "CLMIDIPacket.h"

@implementation CLMIDILogger

- (void)logEvent:(CLMIDIEvent *)event
{
    CLMIDIPacket *packet = event.packet;
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObjects:
        [NSString stringWithFormat:@"RX [%@]", packet.sourceName],
        event.typeName,
        nil];

    if (event.channel != nil) [lines addObject:[NSString stringWithFormat:@"Channel %@", event.channel]];
    if (event.note != nil) [lines addObject:[NSString stringWithFormat:@"Note %@", event.note]];
    if (event.velocity != nil) [lines addObject:[NSString stringWithFormat:@"Velocity %@", event.velocity]];
    if (event.controller != nil) [lines addObject:[NSString stringWithFormat:@"Controller %@", event.controller]];
    if (event.value != nil) [lines addObject:[NSString stringWithFormat:@"Value %@", event.value]];
    if (event.program != nil) [lines addObject:[NSString stringWithFormat:@"Program %@", event.program]];
    if (event.pressure != nil) [lines addObject:[NSString stringWithFormat:@"Pressure %@", event.pressure]];
    if (event.pitchBend != nil) [lines addObject:[NSString stringWithFormat:@"Pitch Bend %@", event.pitchBend]];
    if (event.songPosition != nil) [lines addObject:[NSString stringWithFormat:@"Song Position %@", event.songPosition]];
    if (event.song != nil) [lines addObject:[NSString stringWithFormat:@"Song %@", event.song]];

    [lines addObject:@""];
    [lines addObject:packet.hexString];
    NSLog(@"\n%@", [lines componentsJoinedByString:@"\n"]);
}

@end

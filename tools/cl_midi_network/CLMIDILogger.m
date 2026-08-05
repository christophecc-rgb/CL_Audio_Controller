#import "CLMIDILogger.h"
#import "CLMIDIPacket.h"

@implementation CLMIDILogger

- (void)logPacketList:(const MIDIPacketList *)packetList
           fromSource:(MIDIEndpointRef)source
{
    if (packetList == NULL)
    {
        return;
    }

    NSString *sourceName = [self nameForEndpoint:source];
    const MIDIPacket *packet = &packetList->packet[0];

    for (UInt32 index = 0; index < packetList->numPackets; index++)
    {
        CLMIDIPacket *receivedPacket = [[CLMIDIPacket alloc]
            initWithBytes:packet->data
                   length:packet->length
                timestamp:packet->timeStamp
               sourceName:sourceName];
        [self logPacket:receivedPacket];
        packet = MIDIPacketNext(packet);
    }
}

- (void)logBytes:(const UInt8 *)bytes
          length:(NSUInteger)length
       timestamp:(MIDITimeStamp)timestamp
      sourceName:(NSString *)sourceName
{
    if (bytes == NULL || length == 0)
    {
        return;
    }

    CLMIDIPacket *packet = [[CLMIDIPacket alloc] initWithBytes:bytes
                                                       length:length
                                                    timestamp:timestamp
                                                   sourceName:sourceName];
    [self logPacket:packet];
}

- (void)logPacket:(CLMIDIPacket *)packet
{
    NSString *channelText = packet.channel != nil
        ? [NSString stringWithFormat:@" ch.%@", packet.channel]
        : @"";
    NSLog(@"RX [%@] %@%@ timestamp=%llu length=%lu | %@",
          packet.sourceName,
          packet.messageType,
          channelText,
          (unsigned long long)packet.timestamp,
          (unsigned long)packet.data.length,
          packet.hexString);
}

- (NSString *)nameForEndpoint:(MIDIEndpointRef)endpoint
{
    if (endpoint == 0)
    {
        return @"<unknown>";
    }

    CFStringRef name = NULL;
    OSStatus status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name);
    if (status != noErr || name == NULL)
    {
        status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name);
    }

    if (status != noErr || name == NULL)
    {
        return @"<unknown>";
    }

    return CFBridgingRelease(name);
}

@end

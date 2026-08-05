#import "CLMIDILogger.h"

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
        [self logBytes:packet->data
                length:packet->length
             timestamp:packet->timeStamp
            sourceName:sourceName];
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

    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 3];
    for (NSUInteger index = 0; index < length; index++)
    {
        [hex appendFormat:index == 0 ? @"%02X" : @" %02X", bytes[index]];
    }

    NSString *label = sourceName.length > 0 ? sourceName : @"<unknown>";
    NSLog(@"RX [%@] timestamp=%llu length=%lu | %@",
          label,
          (unsigned long long)timestamp,
          (unsigned long)length,
          hex);
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

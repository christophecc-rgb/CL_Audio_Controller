#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

@class CLMIDIPacket;

NS_ASSUME_NONNULL_BEGIN

@interface CLMIDILogger : NSObject

- (void)logPacketList:(const MIDIPacketList *)packetList
           fromSource:(MIDIEndpointRef)source;

- (void)logBytes:(const UInt8 *)bytes
          length:(NSUInteger)length
       timestamp:(MIDITimeStamp)timestamp
      sourceName:(nullable NSString *)sourceName;

- (void)logPacket:(CLMIDIPacket *)packet;

@end

NS_ASSUME_NONNULL_END

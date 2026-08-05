#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLMIDIPacket : NSObject

@property (nonatomic, copy, readonly) NSData *data;
@property (nonatomic, readonly) MIDITimeStamp timestamp;
@property (nonatomic, copy, readonly) NSString *sourceName;
@property (nonatomic, copy, readonly) NSString *hexString;
@property (nonatomic, copy, readonly) NSString *messageType;
@property (nonatomic, readonly, nullable) NSNumber *channel;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithBytes:(const UInt8 *)bytes
                       length:(NSUInteger)length
                    timestamp:(MIDITimeStamp)timestamp
                   sourceName:(nullable NSString *)sourceName NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

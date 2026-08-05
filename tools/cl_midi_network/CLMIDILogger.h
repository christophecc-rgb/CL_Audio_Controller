#import <Foundation/Foundation.h>
@class CLMIDIPacket;

NS_ASSUME_NONNULL_BEGIN

@interface CLMIDILogger : NSObject

- (void)logPacket:(CLMIDIPacket *)packet;

@end

NS_ASSUME_NONNULL_END

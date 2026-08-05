#import <Foundation/Foundation.h>
@class CLMIDIEvent;

NS_ASSUME_NONNULL_BEGIN

@interface CLMIDILogger : NSObject

- (void)logEvent:(CLMIDIEvent *)event;

@end

NS_ASSUME_NONNULL_END

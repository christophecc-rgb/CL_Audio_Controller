#import <Foundation/Foundation.h>
#import "CLCommand.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, CLLogicTransportStateValue)
{
    CLLogicTransportStateStopped = 1,
    CLLogicTransportStatePlaying,
    CLLogicTransportStateRecording,
    CLLogicTransportStatePaused
};

FOUNDATION_EXPORT NSString *CLLogicTransportStateName(CLLogicTransportStateValue state);

@interface CLLogicTransportState : NSObject

@property (nonatomic, readonly) CLLogicTransportStateValue value;
@property (nonatomic, copy, readonly) NSString *name;

- (BOOL)applyTransportAction:(CLTransportAction)action;

@end
NS_ASSUME_NONNULL_END

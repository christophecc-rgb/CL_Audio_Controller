#import <Foundation/Foundation.h>
#import "CLCommand.h"
#import "CLLogicTransportState.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CLLogicTransportAdapter <NSObject>

- (void)applyTransportAction:(CLTransportAction)action
                       state:(CLLogicTransportStateValue)state;

@end


@interface CLSimulatedLogicTransportAdapter : NSObject <CLLogicTransportAdapter>

@property (nonatomic, readonly) NSUInteger invocationCount;
@property (nonatomic, readonly) CLTransportAction lastAction;
@property (nonatomic, readonly) CLLogicTransportStateValue lastState;

@end
NS_ASSUME_NONNULL_END

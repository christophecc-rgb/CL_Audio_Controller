#import <Foundation/Foundation.h>
#import "CLMIDIFramework.h"
#import "CLLogicTransportAdapter.h"
#import "CLLogicTransportState.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLLogicBridge : NSObject <CLCommandReceiver>

@property (nonatomic, strong, readonly) CLLogicTransportState *transportState;
@property (nonatomic, strong, readonly) id<CLLogicTransportAdapter> transportAdapter;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithTransportAdapter:(id<CLLogicTransportAdapter>)transportAdapter
    NS_DESIGNATED_INITIALIZER;

@end
NS_ASSUME_NONNULL_END

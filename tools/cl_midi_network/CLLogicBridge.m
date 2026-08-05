#import "CLLogicBridge.h"

@implementation CLLogicBridge

- (instancetype)initWithTransportAdapter:(id<CLLogicTransportAdapter>)transportAdapter
{
    self = [super init];
    if (self)
    {
        _transportAdapter = transportAdapter;
        _transportState = [CLLogicTransportState new];
    }
    return self;
}

- (void)receiveCommand:(CLCommand *)command
{
    printf("LOGIC COMMAND %s\n", command.name.uppercaseString.UTF8String);
    if (![command isKindOfClass:CLTransportCommand.class])
    {
        printf("STATE %s (unchanged)\n", self.transportState.name.UTF8String);
        fflush(stdout);
        return;
    }

    CLTransportAction action = ((CLTransportCommand *)command).action;
    BOOL changed = [self.transportState applyTransportAction:action];
    if (changed)
    {
        [self.transportAdapter applyTransportAction:action state:self.transportState.value];
    }
    printf("STATE %s%s\n",
           self.transportState.name.UTF8String,
           changed ? "" : " (unchanged)");
    fflush(stdout);
}

@end

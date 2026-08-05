#import "CLMIDIFramework.h"

@interface CLMIDIMonitor : NSObject <CLCommandReceiver>
@property (nonatomic, strong) CLMIDICore *core;
@property (nonatomic, strong) NSDateFormatter *clock;
@end


@implementation CLMIDIMonitor

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _clock = [NSDateFormatter new];
        _clock.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        _clock.dateFormat = @"HH:mm:ss.SSS";
    }
    return self;
}

- (BOOL)start
{
    self.core = [CLMIDICore new];
    self.core.commandReceiver = self;
    return [self.core startMonitoring];
}

- (void)receiveCommand:(CLCommand *)command
{
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:command.name.uppercaseString];
    if ([command isKindOfClass:CLProgramSelectCommand.class])
    {
        CLProgramSelectCommand *program = (CLProgramSelectCommand *)command;
        if (program.channel != nil) [lines addObject:[NSString stringWithFormat:@"Channel %@", program.channel]];
        [lines addObject:[NSString stringWithFormat:@"Program %lu", (unsigned long)program.program]];
    }
    else if ([command isKindOfClass:CLBankCommand.class])
    {
        CLBankCommand *bank = (CLBankCommand *)command;
        [lines addObject:[NSString stringWithFormat:@"MSB %lu", (unsigned long)bank.msb]];
        [lines addObject:[NSString stringWithFormat:@"LSB %lu", (unsigned long)bank.lsb]];
    }

    NSString *timestamp = [self.clock stringFromDate:[NSDate date]];
    printf("[%s]\n\n%s\n\n", timestamp.UTF8String,
           [[lines componentsJoinedByString:@"\n\n"] UTF8String]);
    fflush(stdout);
}

@end


int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        CLMIDIMonitor *monitor = [CLMIDIMonitor new];
        if (argc == 2 && strcmp(argv[1], "--demo") == 0)
        {
            [monitor receiveCommand:[[CLProgramSelectCommand alloc] initWithProgram:42 channel:@16]];
            [monitor receiveCommand:[[CLStopCommand alloc] init]];
            return 0;
        }
        if (![monitor start]) return 1;
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}

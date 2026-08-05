#import "CLCommand.h"

@implementation CLCommand

- (instancetype)initWithKind:(CLCommandKind)kind name:(NSString *)name
{
    self = [super init];
    if (self)
    {
        _kind = kind;
        _name = [name copy];
    }
    return self;
}

- (NSString *)description
{
    return self.name;
}

@end


@implementation CLTransportCommand

- (instancetype)initWithAction:(CLTransportAction)action
{
    self = [super initWithKind:CLCommandKindTransport name:[self.class nameForAction:action]];
    if (self)
    {
        _action = action;
    }
    return self;
}

+ (NSString *)nameForAction:(CLTransportAction)action
{
    switch (action)
    {
        case CLTransportActionPlay: return @"Play";
        case CLTransportActionStop: return @"Stop";
        case CLTransportActionPause: return @"Pause";
        case CLTransportActionRecord: return @"Record";
        case CLTransportActionClock: return @"Transport Clock";
    }
}

@end


@implementation CLPlayCommand
- (instancetype)init { return [super initWithAction:CLTransportActionPlay]; }
@end

@implementation CLStopCommand
- (instancetype)init { return [super initWithAction:CLTransportActionStop]; }
@end

@implementation CLPauseCommand
- (instancetype)init { return [super initWithAction:CLTransportActionPause]; }
@end

@implementation CLRecordCommand
- (instancetype)init { return [super initWithAction:CLTransportActionRecord]; }
@end


@implementation CLProgramSelectCommand

- (instancetype)initWithProgram:(NSUInteger)program channel:(NSNumber *)channel
{
    self = [super initWithKind:CLCommandKindProgramSelect name:@"Program Select"];
    if (self)
    {
        _program = program;
        _channel = channel;
    }
    return self;
}

@end


@implementation CLSceneRecallCommand

- (instancetype)initWithScene:(NSUInteger)scene
{
    self = [super initWithKind:CLCommandKindSceneRecall name:@"Scene Recall"];
    if (self)
    {
        _scene = scene;
    }
    return self;
}

@end


@implementation CLBankCommand

- (instancetype)initWithBank:(NSUInteger)bank channel:(NSNumber *)channel
{
    return [self initWithMSB:bank LSB:0 channel:channel];
}

- (instancetype)initWithMSB:(NSUInteger)msb LSB:(NSUInteger)lsb channel:(NSNumber *)channel
{
    self = [super initWithKind:CLCommandKindBank name:@"Bank"];
    if (self)
    {
        _msb = msb & 0x7F;
        _lsb = lsb & 0x7F;
        _bank = _msb;
        _channel = channel;
    }
    return self;
}

@end


@implementation CLJogCommand

- (instancetype)initWithDelta:(double)delta
{
    self = [super initWithKind:CLCommandKindJog name:@"Jog"];
    if (self)
    {
        _delta = delta;
    }
    return self;
}

@end

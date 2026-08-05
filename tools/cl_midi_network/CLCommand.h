#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, CLCommandKind)
{
    CLCommandKindTransport = 1,
    CLCommandKindProgramSelect,
    CLCommandKindSceneRecall,
    CLCommandKindBank,
    CLCommandKindJog
};

typedef NS_ENUM(NSUInteger, CLTransportAction)
{
    CLTransportActionPlay = 1,
    CLTransportActionStop,
    CLTransportActionPause,
    CLTransportActionRecord,
    CLTransportActionClock
};

@interface CLCommand : NSObject

@property (nonatomic, readonly) CLCommandKind kind;
@property (nonatomic, copy, readonly) NSString *name;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithKind:(CLCommandKind)kind
                         name:(NSString *)name NS_DESIGNATED_INITIALIZER;

@end


@interface CLTransportCommand : CLCommand

@property (nonatomic, readonly) CLTransportAction action;

- (instancetype)initWithAction:(CLTransportAction)action;

@end


@interface CLPlayCommand : CLTransportCommand
- (instancetype)init;
@end

@interface CLStopCommand : CLTransportCommand
- (instancetype)init;
@end

@interface CLPauseCommand : CLTransportCommand
- (instancetype)init;
@end

@interface CLRecordCommand : CLTransportCommand
- (instancetype)init;
@end


@interface CLProgramSelectCommand : CLCommand

@property (nonatomic, readonly) NSUInteger program;
@property (nonatomic, readonly, nullable) NSNumber *channel;

- (instancetype)initWithProgram:(NSUInteger)program
                         channel:(nullable NSNumber *)channel;

@end


@interface CLSceneRecallCommand : CLCommand

@property (nonatomic, readonly) NSUInteger scene;

- (instancetype)initWithScene:(NSUInteger)scene;

@end


@interface CLBankCommand : CLCommand

@property (nonatomic, readonly) NSUInteger bank;
@property (nonatomic, readonly, nullable) NSNumber *channel;

- (instancetype)initWithBank:(NSUInteger)bank
                      channel:(nullable NSNumber *)channel;

@end


@interface CLJogCommand : CLCommand

@property (nonatomic, readonly) double delta;

- (instancetype)initWithDelta:(double)delta;

@end


@protocol CLCommandReceiver <NSObject>

- (void)receiveCommand:(CLCommand *)command;

@end

NS_ASSUME_NONNULL_END

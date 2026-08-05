#import <Foundation/Foundation.h>

@class CLCommand;
@class CLMIDIEvent;

NS_ASSUME_NONNULL_BEGIN

@protocol CLMIDIEventCommandInterpreting <NSObject>

- (NSArray<CLCommand *> *)commandsForEvent:(CLMIDIEvent *)event;

@end


@interface CLMIDICommandInterpreter : NSObject <CLMIDIEventCommandInterpreting>
@end

NS_ASSUME_NONNULL_END

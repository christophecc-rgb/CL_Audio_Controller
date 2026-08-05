#import <Foundation/Foundation.h>
#import "CLCommand.h"

@class CLMIDIEvent;

@interface CLMIDICore : NSObject

@property (nonatomic, weak) id<CLCommandReceiver> commandReceiver;
@property (nonatomic, copy, nullable) void (^eventHandler)(CLMIDIEvent * _Nonnull event);

- (void)scanPorts;
- (BOOL)startMonitoring;
- (void)stopMonitoring;

@end

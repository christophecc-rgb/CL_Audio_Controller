#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import "CLCommand.h"

@interface CLMIDICore : NSObject

@property (nonatomic, weak) id<CLCommandReceiver> commandReceiver;

- (void)scanPorts;
- (BOOL)startMonitoring;
- (void)stopMonitoring;

@end

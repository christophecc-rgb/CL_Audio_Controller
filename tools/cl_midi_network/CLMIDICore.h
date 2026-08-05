#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

@interface CLMIDICore : NSObject

- (void)scanPorts;
- (BOOL)startMonitoring;
- (void)stopMonitoring;

@end

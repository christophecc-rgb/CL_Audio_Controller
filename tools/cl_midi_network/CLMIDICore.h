#import <Foundation/Foundation.h>

@interface CLMIDICore : NSObject

- (void)scanPorts;
- (void)startMonitoring;

@end

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

@class CLMIDIPacket;
@class CLMIDIPort;

NS_ASSUME_NONNULL_BEGIN

@protocol CLMIDIPortDelegate <NSObject>

- (void)midiPort:(CLMIDIPort *)port didReceivePacket:(CLMIDIPacket *)packet;

@end


@interface CLMIDIPort : NSObject

@property (nonatomic, weak, nullable) id<CLMIDIPortDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithClient:(MIDIClientRef)client
                       delegate:(nullable id<CLMIDIPortDelegate>)delegate NS_DESIGNATED_INITIALIZER;

- (BOOL)open:(NSError * _Nullable * _Nullable)error;
- (void)refreshSources;
- (void)close;

@end

NS_ASSUME_NONNULL_END

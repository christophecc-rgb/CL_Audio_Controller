#import <Foundation/Foundation.h>

@class CLMIDIPacket;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, CLMIDIEventType)
{
    CLMIDIEventTypeUnknown = 0,
    CLMIDIEventTypeData,
    CLMIDIEventTypeNoteOff,
    CLMIDIEventTypeNoteOn,
    CLMIDIEventTypePolyphonicKeyPressure,
    CLMIDIEventTypeControlChange,
    CLMIDIEventTypeProgramChange,
    CLMIDIEventTypeChannelPressure,
    CLMIDIEventTypePitchBend,
    CLMIDIEventTypeSystemExclusive,
    CLMIDIEventTypeMIDITimeCodeQuarterFrame,
    CLMIDIEventTypeSongPositionPointer,
    CLMIDIEventTypeSongSelect,
    CLMIDIEventTypeTuneRequest,
    CLMIDIEventTypeTimingClock,
    CLMIDIEventTypeStart,
    CLMIDIEventTypeContinue,
    CLMIDIEventTypeStop,
    CLMIDIEventTypeActiveSensing,
    CLMIDIEventTypeSystemReset
};

typedef NS_ENUM(NSUInteger, CLMIDIEventProtocol)
{
    CLMIDIEventProtocolMIDI1ByteStream = 1,
    CLMIDIEventProtocolMIDI2UMP = 2
};

@interface CLMIDIEvent : NSObject

@property (nonatomic, strong, readonly) CLMIDIPacket *packet;
@property (nonatomic, readonly) CLMIDIEventType type;
@property (nonatomic, readonly) CLMIDIEventProtocol protocol;
@property (nonatomic, copy, readonly) NSString *typeName;
@property (nonatomic, readonly) UInt8 statusByte;

@property (nonatomic, readonly, nullable) NSNumber *channel;
@property (nonatomic, readonly, nullable) NSNumber *note;
@property (nonatomic, readonly, nullable) NSNumber *velocity;
@property (nonatomic, readonly, nullable) NSNumber *controller;
@property (nonatomic, readonly, nullable) NSNumber *value;
@property (nonatomic, readonly, nullable) NSNumber *program;
@property (nonatomic, readonly, nullable) NSNumber *pressure;
@property (nonatomic, readonly, nullable) NSNumber *pitchBend;
@property (nonatomic, readonly, nullable) NSNumber *pitchBendRaw;
@property (nonatomic, readonly, nullable) NSNumber *songPosition;
@property (nonatomic, readonly, nullable) NSNumber *song;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithPacket:(CLMIDIPacket *)packet NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

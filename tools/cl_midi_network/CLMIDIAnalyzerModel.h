#import <Foundation/Foundation.h>
#import "CLMIDIFramework.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLMIDIAnalyzerRecord : NSObject

@property (nonatomic, strong, readonly) NSDate *receivedAt;
@property (nonatomic, copy, readonly) NSString *direction;
@property (nonatomic, strong, readonly) CLCommand *command;
@property (nonatomic, strong, readonly) CLMIDIEvent *event;
@property (nonatomic, strong, readonly) CLMIDIPacket *packet;

@property (nonatomic, copy, readonly) NSString *timeText;
@property (nonatomic, copy, readonly) NSString *sourceText;
@property (nonatomic, copy, readonly) NSString *commandTypeText;
@property (nonatomic, copy, readonly) NSString *channelText;
@property (nonatomic, copy, readonly) NSString *descriptionText;
@property (nonatomic, copy, readonly) NSString *hexText;
@property (nonatomic, copy, readonly) NSString *detailText;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithCommand:(CLCommand *)command
                           event:(CLMIDIEvent *)event
                       direction:(NSString *)direction
                       timestamp:(NSDate *)timestamp NS_DESIGNATED_INITIALIZER;

@end


@interface CLMIDIAnalyzerSession : NSObject

@property (nonatomic, copy, nullable) NSString *typeFilter;
@property (nonatomic, copy, nullable) NSString *sourceFilter;
@property (nonatomic, copy, nullable) NSString *searchText;
@property (nonatomic, copy, readonly) NSArray<CLMIDIAnalyzerRecord *> *records;
@property (nonatomic, copy, readonly) NSArray<CLMIDIAnalyzerRecord *> *visibleRecords;

- (void)addRecord:(CLMIDIAnalyzerRecord *)record;
- (void)clear;
- (NSString *)textLog;

@end
NS_ASSUME_NONNULL_END

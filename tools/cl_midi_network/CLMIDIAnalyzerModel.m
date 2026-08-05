#import "CLMIDIAnalyzerModel.h"

static NSDateFormatter *CLMIDIAnalyzerClock(void)
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    return formatter;
}

@implementation CLMIDIAnalyzerRecord
{
    NSString *_cachedDetailText;
}

- (instancetype)initWithCommand:(CLCommand *)command
                           event:(CLMIDIEvent *)event
                       direction:(NSString *)direction
                       timestamp:(NSDate *)timestamp
{
    self = [super init];
    if (self)
    {
        _receivedAt = timestamp;
        _direction = [direction copy];
        _event = event;
        _packet = event.packet;
        _timeText = [CLMIDIAnalyzerClock() stringFromDate:timestamp];
        _sourceText = event.packet.sourceName;
        _channelText = event.channel != nil ? event.channel.stringValue : @"—";
        _hexText = event.packet.hexString;
        if (command != nil)
        {
            [self applyCommand:command];
        }
        else
        {
            _commandTypeText = @"(none)";
            _descriptionText = event.typeName;
        }
    }
    return self;
}

+ (NSString *)typeTextForCommand:(CLCommand *)command
{
    if ([command isKindOfClass:CLPlayCommand.class]) return @"PLAY";
    if ([command isKindOfClass:CLStopCommand.class]) return @"STOP";
    if ([command isKindOfClass:CLPauseCommand.class]) return @"PAUSE";
    if ([command isKindOfClass:CLRecordCommand.class]) return @"RECORD";
    if ([command isKindOfClass:CLProgramSelectCommand.class]) return @"PROGRAM";
    if ([command isKindOfClass:CLSceneRecallCommand.class]) return @"SCENE";
    if ([command isKindOfClass:CLBankCommand.class]) return @"BANK";
    if ([command isKindOfClass:CLJogCommand.class]) return @"JOG";
    return command.name.uppercaseString;
}

+ (NSString *)descriptionTextForCommand:(CLCommand *)command
{
    if ([command isKindOfClass:CLTransportCommand.class])
        return [NSString stringWithFormat:@"Transport %@", command.name];
    if ([command isKindOfClass:CLProgramSelectCommand.class])
        return [NSString stringWithFormat:@"Program %lu",
            (unsigned long)((CLProgramSelectCommand *)command).program];
    if ([command isKindOfClass:CLSceneRecallCommand.class])
        return [NSString stringWithFormat:@"Scene %lu",
            (unsigned long)((CLSceneRecallCommand *)command).scene];
    if ([command isKindOfClass:CLBankCommand.class])
    {
        CLBankCommand *bank = (CLBankCommand *)command;
        return [NSString stringWithFormat:@"MSB %lu · LSB %lu",
            (unsigned long)bank.msb, (unsigned long)bank.lsb];
    }
    if ([command isKindOfClass:CLJogCommand.class])
        return [NSString stringWithFormat:@"Delta %.3f", ((CLJogCommand *)command).delta];
    return command.name;
}

+ (NSString *)detailTextForCommand:(CLCommand *)command event:(CLMIDIEvent *)event
{
    CLMIDIPacket *packet = event.packet;
    return [NSString stringWithFormat:
        @"CLCommand\n%@\n\nCLMIDIEvent\nType: %@\nChannel: %@\nProtocol: %lu\n\n"
         "CLMIDIPacket\nSource: %@\nTimestamp: %llu\nLength: %lu bytes\n\n"
         "Hexadecimal Dump\n%@",
        command != nil ? [self descriptionTextForCommand:command] : @"(none)",
        event.typeName,
        event.channel ?: @"—",
        (unsigned long)event.protocol,
        packet.sourceName,
        (unsigned long long)packet.timestamp,
        (unsigned long)packet.data.length,
        packet.hexString];
}

- (void)applyCommand:(CLCommand *)command
{
    _command = command;
    _commandTypeText = [self.class typeTextForCommand:command];
    _descriptionText = [self.class descriptionTextForCommand:command];
    _cachedDetailText = nil;
}

- (NSString *)detailText
{
    if (_cachedDetailText == nil)
        _cachedDetailText = [self.class detailTextForCommand:self.command event:self.event];
    return _cachedDetailText;
}

@end


@interface CLMIDIAnalyzerSession ()
@property (nonatomic, strong) NSMutableArray<CLMIDIAnalyzerRecord *> *mutableRecords;
@property (nonatomic, copy) NSArray<CLMIDIAnalyzerRecord *> *cachedVisibleRecords;
@end

@implementation CLMIDIAnalyzerSession

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _mutableRecords = [NSMutableArray array];
        _cachedVisibleRecords = @[];
        _maximumRecordCount = 10000;
    }
    return self;
}

- (NSArray<CLMIDIAnalyzerRecord *> *)records
{
    return self.mutableRecords.copy;
}

- (NSArray<CLMIDIAnalyzerRecord *> *)visibleRecords
{
    return self.cachedVisibleRecords;
}

- (BOOL)isRecordVisible:(CLMIDIAnalyzerRecord *)record
{
    if (self.typeFilter.length > 0 &&
        [record.commandTypeText rangeOfString:self.typeFilter options:NSCaseInsensitiveSearch].location == NSNotFound)
        return NO;
    if (self.sourceFilter.length > 0 &&
        [record.sourceText rangeOfString:self.sourceFilter options:NSCaseInsensitiveSearch].location == NSNotFound)
        return NO;
    if (self.searchText.length > 0)
    {
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@",
            record.sourceText, record.commandTypeText, record.descriptionText, record.hexText];
        if ([haystack rangeOfString:self.searchText options:NSCaseInsensitiveSearch].location == NSNotFound)
            return NO;
    }
    return YES;
}

- (void)rebuildVisibleRecords
{
    NSPredicate *predicate = [NSPredicate predicateWithBlock:
        ^BOOL(CLMIDIAnalyzerRecord *record, NSDictionary *bindings) {
            (void)bindings;
            return [self isRecordVisible:record];
        }];
    self.cachedVisibleRecords = [self.mutableRecords filteredArrayUsingPredicate:predicate];
}

- (void)addRecord:(CLMIDIAnalyzerRecord *)record
{
    [self addRecords:@[record]];
}

- (void)addRecords:(NSArray<CLMIDIAnalyzerRecord *> *)records
{
    if (records.count == 0) return;
    [self.mutableRecords addObjectsFromArray:records];
    if (self.maximumRecordCount > 0 && self.mutableRecords.count > self.maximumRecordCount)
    {
        NSUInteger excess = self.mutableRecords.count - self.maximumRecordCount;
        [self.mutableRecords removeObjectsInRange:NSMakeRange(0, excess)];
    }
    [self rebuildVisibleRecords];
}

- (void)setMaximumRecordCount:(NSUInteger)maximumRecordCount
{
    _maximumRecordCount = maximumRecordCount;
    if (maximumRecordCount > 0 && self.mutableRecords.count > maximumRecordCount)
    {
        NSUInteger excess = self.mutableRecords.count - maximumRecordCount;
        [self.mutableRecords removeObjectsInRange:NSMakeRange(0, excess)];
    }
    [self rebuildVisibleRecords];
}

- (void)setTypeFilter:(NSString *)typeFilter
{
    _typeFilter = [typeFilter copy];
    [self rebuildVisibleRecords];
}

- (void)setSourceFilter:(NSString *)sourceFilter
{
    _sourceFilter = [sourceFilter copy];
    [self rebuildVisibleRecords];
}

- (void)setSearchText:(NSString *)searchText
{
    _searchText = [searchText copy];
    [self rebuildVisibleRecords];
}

- (CLMIDIAnalyzerRecord *)recordForEvent:(CLMIDIEvent *)event
{
    for (CLMIDIAnalyzerRecord *record in self.mutableRecords.reverseObjectEnumerator)
    {
        if (record.event == event) return record;
    }
    return nil;
}

- (void)clear
{
    [self.mutableRecords removeAllObjects];
    self.cachedVisibleRecords = @[];
}

- (NSString *)textLog
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (CLMIDIAnalyzerRecord *record in self.records)
    {
        [lines addObject:[@[record.timeText, record.direction, record.sourceText,
            record.commandTypeText, record.channelText, record.descriptionText, record.hexText]
            componentsJoinedByString:@"\t"]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end

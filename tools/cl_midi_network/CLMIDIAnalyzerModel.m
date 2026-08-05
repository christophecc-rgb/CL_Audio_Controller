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
            _detailText = [self.class detailTextForCommand:nil event:event];
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
    _detailText = [self.class detailTextForCommand:command event:self.event];
}

@end


@interface CLMIDIAnalyzerSession ()
@property (nonatomic, strong) NSMutableArray<CLMIDIAnalyzerRecord *> *mutableRecords;
@end

@implementation CLMIDIAnalyzerSession

- (instancetype)init
{
    self = [super init];
    if (self) _mutableRecords = [NSMutableArray array];
    return self;
}

- (NSArray<CLMIDIAnalyzerRecord *> *)records
{
    return self.mutableRecords.copy;
}

- (NSArray<CLMIDIAnalyzerRecord *> *)visibleRecords
{
    NSPredicate *predicate = [NSPredicate predicateWithBlock:
        ^BOOL(CLMIDIAnalyzerRecord *record, NSDictionary *bindings) {
            (void)bindings;
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
        }];
    return [self.mutableRecords filteredArrayUsingPredicate:predicate];
}

- (void)addRecord:(CLMIDIAnalyzerRecord *)record
{
    [self.mutableRecords addObject:record];
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

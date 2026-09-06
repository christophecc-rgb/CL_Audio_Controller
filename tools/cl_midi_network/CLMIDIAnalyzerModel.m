#import "CLMIDIAnalyzerModel.h"

static NSUInteger CLMIDIAnalyzerMessageLength(UInt8 status)
{
    if (status < 0x80) return 0;
    if (status < 0xF0)
        return (status & 0xE0) == 0xC0 ? 2 : 3;
    switch (status)
    {
        case 0xF0: return NSNotFound;
        case 0xF1: return 2;
        case 0xF2: return 3;
        case 0xF3: return 2;
        case 0xF6:
        case 0xF7:
        case 0xF8:
        case 0xF9:
        case 0xFA:
        case 0xFB:
        case 0xFC:
        case 0xFD:
        case 0xFE:
        case 0xFF: return 1;
        default: return 1;
    }
}

@interface CLMIDIAnalyzerPacketParser ()
@property (nonatomic) UInt8 runningStatus;
@property (nonatomic, strong) NSMutableData *pendingMessage;
@property (nonatomic) NSUInteger pendingLength;
@property (nonatomic) BOOL inSystemExclusive;
@end

@implementation CLMIDIAnalyzerPacketParser

- (instancetype)init
{
    self = [super init];
    if (self) _pendingMessage = [NSMutableData data];
    return self;
}

- (void)reset
{
    self.runningStatus = 0;
    self.pendingLength = 0;
    self.inSystemExclusive = NO;
    [self.pendingMessage setLength:0];
}

- (void)addEventWithData:(NSData *)data
                  packet:(CLMIDIPacket *)packet
                  events:(NSMutableArray<CLMIDIEvent *> *)events
{
    UInt8 messageBytes[data.length];
    [data getBytes:messageBytes length:data.length];
    CLMIDIPacket *messagePacket = [[CLMIDIPacket alloc]
        initWithBytes:messageBytes
               length:data.length
            timestamp:packet.timestamp
           sourceName:packet.sourceName];
    [events addObject:[[CLMIDIEvent alloc] initWithPacket:messagePacket]];
}

- (void)finishPendingForPacket:(CLMIDIPacket *)packet
                         events:(NSMutableArray<CLMIDIEvent *> *)events
{
    [self addEventWithData:self.pendingMessage.copy packet:packet events:events];
    [self.pendingMessage setLength:0];
    self.pendingLength = 0;
}

- (NSArray<CLMIDIEvent *> *)eventsForPacket:(CLMIDIPacket *)packet
{
    NSMutableArray<CLMIDIEvent *> *events = [NSMutableArray array];
    UInt8 bytes[packet.data.length];
    [packet.data getBytes:bytes length:packet.data.length];
    for (NSUInteger index = 0; index < packet.data.length; index++)
    {
        UInt8 byte = bytes[index];

        // Realtime messages may occur anywhere and do not disturb parser state.
        if (byte >= 0xF8)
        {
            NSData *data = [NSData dataWithBytes:&byte length:1];
            [self addEventWithData:data packet:packet events:events];
            continue;
        }

        if (self.inSystemExclusive)
        {
            [self.pendingMessage appendBytes:&byte length:1];
            if (byte == 0xF7)
            {
                self.inSystemExclusive = NO;
                [self finishPendingForPacket:packet events:events];
            }
            continue;
        }

        if (byte >= 0x80)
        {
            [self.pendingMessage setLength:0];
            self.pendingLength = CLMIDIAnalyzerMessageLength(byte);
            [self.pendingMessage appendBytes:&byte length:1];
            if (byte < 0xF0)
                self.runningStatus = byte;
            else
                self.runningStatus = 0;

            if (byte == 0xF0)
            {
                self.inSystemExclusive = YES;
                continue;
            }
            if (self.pendingLength == 1)
                [self finishPendingForPacket:packet events:events];
            continue;
        }

        if (self.pendingMessage.length == 0)
        {
            if (self.runningStatus == 0)
            {
                NSData *data = [NSData dataWithBytes:&byte length:1];
                [self addEventWithData:data packet:packet events:events];
                continue;
            }
            UInt8 status = self.runningStatus;
            self.pendingLength = CLMIDIAnalyzerMessageLength(status);
            [self.pendingMessage appendBytes:&status length:1];
        }
        [self.pendingMessage appendBytes:&byte length:1];
        if (self.pendingMessage.length == self.pendingLength)
            [self finishPendingForPacket:packet events:events];
    }
    return events;
}

@end

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
        _commandTypeText = event.typeName;
        _channelText = event.channel != nil ? event.channel.stringValue : @"—";
        _hexText = event.packet.hexString;
        _descriptionText = [self.class descriptionTextForEvent:event];
        if (command != nil)
        {
            [self applyCommand:command];
        }
    }
    return self;
}

+ (NSString *)descriptionTextForEvent:(CLMIDIEvent *)event
{
    if (event.controller != nil)
        return [NSString stringWithFormat:@"CC %@ = %@", event.controller, event.value ?: @"—"];
    if (event.note != nil)
    {
        if (event.pressure != nil)
            return [NSString stringWithFormat:@"Note %@ · pression %@", event.note, event.pressure];
        return [NSString stringWithFormat:@"Note %@ · vélocité %@", event.note, event.velocity ?: @"—"];
    }
    if (event.program != nil)
        return [NSString stringWithFormat:@"Program %@", event.program];
    if (event.pressure != nil)
        return [NSString stringWithFormat:@"Pression %@", event.pressure];
    if (event.pitchBend != nil)
        return [NSString stringWithFormat:@"Pitch Bend %@", event.pitchBend];
    if (event.songPosition != nil)
        return [NSString stringWithFormat:@"Song Position %@", event.songPosition];
    if (event.song != nil)
        return [NSString stringWithFormat:@"Song %@", event.song];
    if (event.value != nil)
        return [NSString stringWithFormat:@"Value %@", event.value];
    return event.typeName;
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
        [record.commandTypeText caseInsensitiveCompare:self.typeFilter] != NSOrderedSame)
        return NO;
    if (self.channelFilter != nil && ![record.event.channel isEqualToNumber:self.channelFilter])
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

- (void)refreshVisibleRecords
{
    [self rebuildVisibleRecords];
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

- (void)setChannelFilter:(NSNumber *)channelFilter
{
    _channelFilter = channelFilter;
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

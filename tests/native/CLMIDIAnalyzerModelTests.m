#import <Foundation/Foundation.h>
#import "CLMIDIAnalyzerModel.h"

static CLMIDIEvent *Event(const UInt8 *bytes, NSUInteger length, NSString *source)
{
    CLMIDIPacket *packet = [[CLMIDIPacket alloc] initWithBytes:bytes
                                                       length:length
                                                    timestamp:99
                                                   sourceName:source];
    return [[CLMIDIEvent alloc] initWithPacket:packet];
}

int main(void)
{
    @autoreleasepool
    {
        CLMIDIAnalyzerSession *session = [CLMIDIAnalyzerSession new];
        const UInt8 programBytes[] = {0xCF, 42};
        CLMIDIEvent *programEvent = Event(programBytes, sizeof(programBytes), @"Logic Pro");
        CLCommand *program = [[CLProgramSelectCommand alloc] initWithProgram:42 channel:@16];
        CLMIDIAnalyzerRecord *programRecord = [[CLMIDIAnalyzerRecord alloc]
            initWithCommand:program event:programEvent direction:@"RX" timestamp:[NSDate dateWithTimeIntervalSince1970:0]];
        [session addRecord:programRecord];

        NSCAssert([programRecord.commandTypeText isEqualToString:@"PROGRAM"], @"Expected PROGRAM");
        NSCAssert([programRecord.channelText isEqualToString:@"16"], @"Expected channel 16");
        NSCAssert([programRecord.descriptionText isEqualToString:@"Program 42"], @"Expected program 42");
        NSCAssert([programRecord.hexText isEqualToString:@"CF 2A"], @"Expected raw dump");
        NSCAssert([programRecord.sourceText isEqualToString:@"Logic Pro"], @"Expected source");
        NSCAssert([programRecord.detailText containsString:@"CLCommand"], @"Missing command detail");
        NSCAssert([programRecord.detailText containsString:@"CLMIDIEvent"], @"Missing event detail");
        NSCAssert([programRecord.detailText containsString:@"CLMIDIPacket"], @"Missing packet detail");

        const UInt8 stopBytes[] = {0xFC};
        CLMIDIEvent *stopEvent = Event(stopBytes, sizeof(stopBytes), @"Ableton Live");
        CLMIDIAnalyzerRecord *stopRecord = [[CLMIDIAnalyzerRecord alloc]
            initWithCommand:[[CLStopCommand alloc] init]
                       event:stopEvent
                   direction:@"RX"
                   timestamp:[NSDate dateWithTimeIntervalSince1970:1]];
        [session addRecord:stopRecord];
        NSCAssert(session.records.count == 2, @"Expected two records");

        session.typeFilter = @"program";
        NSCAssert(session.visibleRecords.count == 1, @"Type filter failed");
        session.typeFilter = nil;
        session.sourceFilter = @"Ableton";
        NSCAssert(session.visibleRecords.firstObject == stopRecord, @"Source filter failed");
        session.sourceFilter = nil;
        session.searchText = @"CF 2A";
        NSCAssert(session.visibleRecords.firstObject == programRecord, @"Search failed");
        NSCAssert([session.textLog containsString:@"Program 42"], @"Text export failed");

        [session clear];
        NSCAssert(session.records.count == 0, @"Clear failed");
    }
    return 0;
}

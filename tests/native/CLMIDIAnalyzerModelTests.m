#import <Foundation/Foundation.h>
#import "CLMIDIAnalyzerModel.h"
#import "CLMIDICommandInterpreter.h"

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

        session.maximumRecordCount = 2;
        [session addRecords:@[programRecord, stopRecord, programRecord]];
        NSCAssert(session.records.count == 2, @"Retention limit failed");
        NSCAssert(session.records.firstObject == stopRecord, @"Retention must discard oldest rows");
        NSArray<CLMIDIAnalyzerRecord *> *cachedRows = session.visibleRecords;
        NSCAssert(cachedRows == session.visibleRecords, @"Visible row cache was rebuilt unnecessarily");
        session.maximumRecordCount = 0;
        [session clear];

        const UInt8 noteOnBytes[] = {0x90, 60, 100};
        const UInt8 noteOffBytes[] = {0x80, 60, 0};
        const UInt8 pitchBendBytes[] = {0xE0, 0, 64};
        const UInt8 sysExBytes[] = {0xF0, 0x43, 0x10, 0xF7};
        const UInt8 activeSenseBytes[] = {0xFE};
        const UInt8 allProgramBytes[] = {0xCF, 42};
        CLMIDIEvent *allEvents[] = {
            Event(noteOnBytes, sizeof(noteOnBytes), @"Test"),
            Event(noteOffBytes, sizeof(noteOffBytes), @"Test"),
            Event(pitchBendBytes, sizeof(pitchBendBytes), @"Test"),
            Event(sysExBytes, sizeof(sysExBytes), @"Test"),
            Event(activeSenseBytes, sizeof(activeSenseBytes), @"Test"),
            Event(allProgramBytes, sizeof(allProgramBytes), @"Test")
        };
        CLMIDICommandInterpreter *interpreter = [CLMIDICommandInterpreter new];
        NSUInteger producedCommandCount = 0;
        for (NSUInteger index = 0; index < 6; index++)
        {
            CLMIDIAnalyzerRecord *record = [[CLMIDIAnalyzerRecord alloc]
                initWithCommand:nil
                           event:allEvents[index]
                       direction:@"RX"
                       timestamp:[NSDate date]];
            [session addRecord:record];
            NSArray<CLCommand *> *commands = [interpreter commandsForEvent:allEvents[index]];
            if (commands.firstObject != nil)
            {
                [record applyCommand:commands.firstObject];
                producedCommandCount += commands.count;
            }
        }
        NSCAssert(session.records.count == 6, @"Every MIDI event must produce one row");
        NSCAssert(producedCommandCount == 1, @"Only Program Change should produce a command");
        for (NSUInteger index = 0; index < 5; index++)
        {
            CLMIDIAnalyzerRecord *record = session.records[index];
            NSCAssert(record.command == nil, @"Non-command event unexpectedly has a command");
            NSCAssert([record.detailText containsString:@"CLCommand\n(none)"],
                      @"Missing explicit command absence");
        }
        CLMIDIAnalyzerRecord *correlatedProgram = session.records[5];
        NSCAssert(correlatedProgram.command != nil, @"Program command was not correlated");
        NSCAssert([correlatedProgram.commandTypeText isEqualToString:@"PROGRAM"],
                  @"Program row was not enriched");
    }
    return 0;
}

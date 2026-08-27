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

static NSArray<CLMIDIEvent *> *Events(CLMIDIAnalyzerPacketParser *parser,
                                      const UInt8 *bytes, NSUInteger length)
{
    CLMIDIPacket *packet = [[CLMIDIPacket alloc] initWithBytes:bytes
                                                       length:length
                                                    timestamp:99
                                                   sourceName:@"Test"];
    return [parser eventsForPacket:packet];
}

int main(void)
{
    @autoreleasepool
    {
        CLMIDIAnalyzerSession *session = [CLMIDIAnalyzerSession new];
        CLMIDIAnalyzerPacketParser *parser = [CLMIDIAnalyzerPacketParser new];

        const UInt8 twoPrograms[] = {0xC1, 0x4F, 0xC0, 0x53};
        NSArray<CLMIDIEvent *> *programEvents = Events(parser, twoPrograms, sizeof(twoPrograms));
        NSCAssert(programEvents.count == 2, @"Expected two Program Change events");
        NSCAssert(programEvents[0].type == CLMIDIEventTypeProgramChange &&
                  programEvents[0].channel.unsignedIntegerValue == 2 &&
                  programEvents[0].program.unsignedIntegerValue == 79,
                  @"First Program Change was decoded incorrectly");
        NSCAssert([programEvents[0].packet.hexString isEqualToString:@"C1 4F"],
                  @"First Program Change hex must be message-scoped");
        NSCAssert(programEvents[1].channel.unsignedIntegerValue == 1 &&
                  programEvents[1].program.unsignedIntegerValue == 83,
                  @"Second Program Change was decoded incorrectly");
        NSCAssert([programEvents[1].packet.hexString isEqualToString:@"C0 53"],
                  @"Second Program Change hex must be message-scoped");

        const UInt8 bankPrograms[] = {0xB1, 0x00, 0x00, 0xB1, 0x20, 0x00, 0xC1, 0x54, 0xC0, 0x5A};
        NSArray<CLMIDIEvent *> *bankProgramEvents = Events(parser, bankPrograms, sizeof(bankPrograms));
        NSCAssert(bankProgramEvents.count == 4, @"Expected every packed MIDI message");
        NSCAssert(bankProgramEvents[0].controller.unsignedIntegerValue == 0 &&
                  bankProgramEvents[1].controller.unsignedIntegerValue == 32,
                  @"Bank Select messages were lost");
        NSCAssert(bankProgramEvents[2].channel.unsignedIntegerValue == 2 &&
                  bankProgramEvents[3].channel.unsignedIntegerValue == 1,
                  @"Program Change channels were decoded incorrectly");

        const UInt8 realtimeInterleaved[] = {0xC1, 0xF8, 0x4F, 0xC0, 0x53};
        NSArray<CLMIDIEvent *> *realtimeEvents = Events(parser, realtimeInterleaved,
                                                       sizeof(realtimeInterleaved));
        NSCAssert(realtimeEvents.count == 3, @"Realtime must not cause event loss");
        NSCAssert(realtimeEvents[0].type == CLMIDIEventTypeTimingClock,
                  @"Interleaved realtime must be a separate event");
        NSCAssert(realtimeEvents[1].program.unsignedIntegerValue == 79 &&
                  realtimeEvents[2].program.unsignedIntegerValue == 83,
                  @"Realtime interrupted Program Change parsing");

        const UInt8 runningPrograms[] = {0xC1, 0x4F, 0x50};
        NSArray<CLMIDIEvent *> *runningEvents = Events(parser, runningPrograms, sizeof(runningPrograms));
        NSCAssert(runningEvents.count == 2 &&
                  [runningEvents[1].packet.hexString isEqualToString:@"C1 50"],
                  @"Running status Program Change was not reconstructed");

        const UInt8 variableLengths[] = {0xD0, 0x44, 0xE1, 0x00, 0x40};
        NSArray<CLMIDIEvent *> *variableEvents = Events(parser, variableLengths,
                                                       sizeof(variableLengths));
        NSCAssert(variableEvents.count == 2 &&
                  variableEvents[0].type == CLMIDIEventTypeChannelPressure &&
                  variableEvents[1].type == CLMIDIEventTypePitchBend,
                  @"Two- and three-byte Channel Voice lengths were not respected");

        const UInt8 runningStart[] = {0xB1, 0x07};
        const UInt8 runningFinish[] = {0x64, 0x08, 0x65};
        NSCAssert(Events(parser, runningStart, sizeof(runningStart)).count == 0,
                  @"An incomplete cross-packet message must wait for its data");
        NSArray<CLMIDIEvent *> *crossPacketEvents = Events(parser, runningFinish,
                                                          sizeof(runningFinish));
        NSCAssert(crossPacketEvents.count == 2 &&
                  crossPacketEvents[0].controller.unsignedIntegerValue == 7 &&
                  crossPacketEvents[1].controller.unsignedIntegerValue == 8,
                  @"Running status across packet boundaries lost events");
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
        session.channelFilter = @16;
        NSCAssert(session.visibleRecords.firstObject == programRecord && session.visibleRecords.count == 1,
                  @"Channel filter failed");
        session.channelFilter = @2;
        NSCAssert(session.visibleRecords.count == 0, @"Channel filter must hide other channels");
        session.channelFilter = nil;
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

        [session clear];
        session.typeFilter = @"program";
        CLMIDIAnalyzerRecord *deferredProgram = [[CLMIDIAnalyzerRecord alloc]
            initWithCommand:nil event:programEvent direction:@"RX" timestamp:[NSDate date]];
        [session addRecord:deferredProgram];
        NSCAssert(session.visibleRecords.count == 0,
                  @"Raw event must not match the program filter yet");
        [deferredProgram applyCommand:program];
        [session refreshVisibleRecords];
        NSCAssert(session.visibleRecords.firstObject == deferredProgram,
                  @"Enriched Program Change must become visible immediately");
    }
    return 0;
}

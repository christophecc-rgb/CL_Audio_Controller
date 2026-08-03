#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

static MIDIPortRef outputPort = 0;
static MIDIEndpointRef destination = 0;
static UInt8 expectedProgram = 41;
static UInt8 expectedChannel = 1;
static BOOL received = NO;
static NSUInteger matchingReturnCount = 0;
static NSUInteger totalProgramChangeCount = 0;
static NSUInteger ignoredLocalEchoCount = 0;
static CFAbsoluteTime firstMatchAt = 0;
static CFAbsoluteTime sentAt = 0;
static double minimumReturnLatencyMs = 35.0;

static NSString *endpointName(MIDIEndpointRef endpoint) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || value == NULL) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    }
    return CFBridgingRelease(value) ?: @"";
}

static MIDIEndpointRef findEndpoint(BOOL source, NSString *preferredName) {
    ItemCount count = source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
    for (ItemCount index = 0; index < count; index++) {
        MIDIEndpointRef endpoint = source ? MIDIGetSource(index) : MIDIGetDestination(index);
        NSString *name = endpointName(endpoint);
        fprintf(stdout, "MIDI_%s index=%lu name=%s\n", source ? "SOURCE" : "DESTINATION",
                (unsigned long)index, name.UTF8String);
        if ([name rangeOfString:preferredName options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return endpoint;
        }
    }
    return 0;
}

static void midiRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)readProcRefCon;
    (void)srcConnRefCon;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        for (UInt16 index = 0; index + 1 < packet->length; index++) {
            UInt8 status = packet->data[index];
            UInt8 program = packet->data[index + 1];
            if ((status & 0xF0) == 0xC0) {
                double latencyMs = (CFAbsoluteTimeGetCurrent() - sentAt) * 1000.0;
                BOOL exactMatch = program == expectedProgram && ((status & 0x0F) + 1) == expectedChannel;
                // CoreMIDI may mirror the packet just written to the paired
                // source before it crosses the network. This is not a remote
                // console confirmation and must not count as a MIDI loop.
                if (exactMatch && latencyMs >= 0 && latencyMs < minimumReturnLatencyMs) {
                    ignoredLocalEchoCount += 1;
                    if (ignoredLocalEchoCount <= 16) {
                        fprintf(stdout, "IGNORED_LOCAL_ECHO channel=%u program=%u latency_ms=%.1f\n",
                                (status & 0x0F) + 1, program, latencyMs);
                        fflush(stdout);
                    }
                    index += 1;
                    continue;
                }
                totalProgramChangeCount += 1;
                if (totalProgramChangeCount <= 16) {
                    fprintf(stdout, "RETURN channel=%u program=%u scene=%u latency_ms=%.1f match=%s\n",
                            (status & 0x0F) + 1, program, program + 1, latencyMs,
                            exactMatch ? "yes" : "no");
                    fflush(stdout);
                }
                if (exactMatch) {
                    matchingReturnCount += 1;
                    if (!received) firstMatchAt = CFAbsoluteTimeGetCurrent();
                    received = YES;
                }
                index += 1;
            }
        }
        packet = MIDIPacketNext(packet);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--help"]) {
            puts("Usage: CLMIDIRoundTripTester [--endpoint NAME] [--program 42] [--channel 1] [--timeout 5]");
            return 0;
        }
        NSString *endpointSearchName = @"Session RTP 1";
        NSUInteger sceneNumber = 42;
        double timeout = 5.0;
        NSUInteger position = [arguments indexOfObject:@"--endpoint"];
        if (position != NSNotFound && position + 1 < arguments.count) endpointSearchName = arguments[position + 1];
        position = [arguments indexOfObject:@"--program"];
        if (position != NSNotFound && position + 1 < arguments.count) sceneNumber = [arguments[position + 1] integerValue];
        position = [arguments indexOfObject:@"--channel"];
        if (position != NSNotFound && position + 1 < arguments.count) expectedChannel = (UInt8)[arguments[position + 1] integerValue];
        position = [arguments indexOfObject:@"--timeout"];
        if (position != NSNotFound && position + 1 < arguments.count) timeout = [arguments[position + 1] doubleValue];
        if (sceneNumber < 1 || sceneNumber > 128) {
            fputs("Program must be in the user-facing range 1...128\n", stderr);
            return 2;
        }
        if (expectedChannel < 1 || expectedChannel > 16) {
            fputs("Channel must be in the range 1...16\n", stderr);
            return 2;
        }
        expectedProgram = (UInt8)(sceneNumber - 1);

        // Initialise CoreMIDI before enumerating endpoints.  A standalone
        // diagnostic must not depend on another MIDI application already
        // having loaded the server and its network driver.
        MIDIClientRef client = 0;
        OSStatus clientStatus = MIDIClientCreate(CFSTR("CL MIDI Round Trip Tester"), NULL, NULL, &client);
        if (clientStatus != noErr) {
            fprintf(stderr, "COREMIDI_CLIENT_ERROR status=%d\n", (int)clientStatus);
            return 3;
        }

        MIDIEndpointRef source = findEndpoint(YES, endpointSearchName);
        destination = findEndpoint(NO, endpointSearchName);
        if (source == 0 || destination == 0) {
            fprintf(stderr, "RTP_ENDPOINTS_NOT_FOUND name=%s source=%s destination=%s\n",
                    endpointSearchName.UTF8String, source ? "yes" : "no", destination ? "yes" : "no");
            MIDIClientDispose(client);
            return 4;
        }

        MIDIPortRef inputPort = 0;
        OSStatus inputStatus = MIDIInputPortCreate(client, CFSTR("RTP return"), midiRead, NULL, &inputPort);
        OSStatus outputStatus = MIDIOutputPortCreate(client, CFSTR("RTP test send"), &outputPort);
        if (inputStatus != noErr || outputStatus != noErr) {
            fprintf(stderr, "COREMIDI_PORT_ERROR input_status=%d output_status=%d\n",
                    (int)inputStatus, (int)outputStatus);
            if (inputPort) MIDIPortDispose(inputPort);
            if (outputPort) MIDIPortDispose(outputPort);
            MIDIClientDispose(client);
            return 5;
        }
        OSStatus connectStatus = MIDIPortConnectSource(inputPort, source, NULL);
        if (connectStatus != noErr) {
            fprintf(stderr, "COREMIDI_SOURCE_CONNECT_ERROR status=%d\n", (int)connectStatus);
            MIDIPortDispose(inputPort);
            MIDIPortDispose(outputPort);
            MIDIClientDispose(client);
            return 6;
        }

        Byte storage[1024];
        MIDIPacketList *packetList = (MIDIPacketList *)storage;
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        UInt8 message[2] = {(UInt8)(0xC0 | (expectedChannel - 1)), expectedProgram};
        MIDIPacketListAdd(packetList, sizeof(storage), packet, 0, 2, message);
        sentAt = CFAbsoluteTimeGetCurrent();
        OSStatus sendStatus = MIDISend(outputPort, destination, packetList);
        fprintf(stdout, "SENT channel=%u program=%u scene=%lu status=%d\n",
                expectedChannel, expectedProgram, (unsigned long)sceneNumber, (int)sendStatus);
        fflush(stdout);
        if (sendStatus != noErr) {
            fprintf(stderr, "COREMIDI_SEND_ERROR status=%d\n", (int)sendStatus);
            MIDIPortDisconnectSource(inputPort, source);
            MIDIPortDispose(inputPort);
            MIDIPortDispose(outputPort);
            MIDIClientDispose(client);
            return 7;
        }

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (!received && deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (received) {
            NSDate *observationDeadline = [NSDate dateWithTimeIntervalSinceNow:0.50];
            while (observationDeadline.timeIntervalSinceNow > 0) {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            }
        }
        MIDIPortDisconnectSource(inputPort, source);
        MIDIPortDispose(inputPort);
        MIDIPortDispose(outputPort);
        MIDIClientDispose(client);
        if (!received) {
            fprintf(stderr, "TIMEOUT scene=%lu timeout_s=%.1f sent=yes ignored_local_echoes=%lu received_program_changes=%lu\n",
                    (unsigned long)sceneNumber, timeout, (unsigned long)ignoredLocalEchoCount,
                    (unsigned long)totalProgramChangeCount);
            return 8;
        }
        double firstLatencyMs = (firstMatchAt - sentAt) * 1000.0;
        fprintf(stdout, "SUMMARY matching_returns=%lu total_program_changes=%lu ignored_local_echoes=%lu observation_ms=500 first_latency_ms=%.1f\n",
                (unsigned long)matchingReturnCount, (unsigned long)totalProgramChangeCount,
                (unsigned long)ignoredLocalEchoCount, firstLatencyMs);
        if (matchingReturnCount > 4 || totalProgramChangeCount > 16) {
            fprintf(stderr, "LOOP_DETECTED matching_returns=%lu total_program_changes=%lu\n",
                    (unsigned long)matchingReturnCount, (unsigned long)totalProgramChangeCount);
            return 9;
        }
    }
    return 0;
}

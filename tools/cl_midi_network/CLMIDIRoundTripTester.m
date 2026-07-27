#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

static MIDIPortRef outputPort = 0;
static MIDIEndpointRef destination = 0;
static UInt8 expectedProgram = 41;
static BOOL received = NO;
static CFAbsoluteTime sentAt = 0;

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
                fprintf(stdout, "RETURN channel=%u program=%u scene=%u latency_ms=%.1f match=%s\n",
                        (status & 0x0F) + 1, program, program + 1, latencyMs,
                        program == expectedProgram ? "yes" : "no");
                fflush(stdout);
                if (program == expectedProgram) received = YES;
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
            puts("Usage: CLMIDIRoundTripTester [--endpoint NAME] [--program 42] [--timeout 5]");
            return 0;
        }
        NSString *endpointSearchName = @"Session RTP 1";
        NSUInteger sceneNumber = 42;
        double timeout = 5.0;
        NSUInteger position = [arguments indexOfObject:@"--endpoint"];
        if (position != NSNotFound && position + 1 < arguments.count) endpointSearchName = arguments[position + 1];
        position = [arguments indexOfObject:@"--program"];
        if (position != NSNotFound && position + 1 < arguments.count) sceneNumber = [arguments[position + 1] integerValue];
        position = [arguments indexOfObject:@"--timeout"];
        if (position != NSNotFound && position + 1 < arguments.count) timeout = [arguments[position + 1] doubleValue];
        if (sceneNumber < 1 || sceneNumber > 128) {
            fputs("Program must be in the user-facing range 1...128\n", stderr);
            return 2;
        }
        expectedProgram = (UInt8)(sceneNumber - 1);

        MIDIEndpointRef source = findEndpoint(YES, endpointSearchName);
        destination = findEndpoint(NO, endpointSearchName);
        if (source == 0 || destination == 0) {
            fprintf(stderr, "RTP endpoints not found for name: %s\n", endpointSearchName.UTF8String);
            return 3;
        }

        MIDIClientRef client = 0;
        MIDIPortRef inputPort = 0;
        MIDIClientCreate(CFSTR("CL MIDI Round Trip Tester"), NULL, NULL, &client);
        MIDIInputPortCreate(client, CFSTR("RTP return"), midiRead, NULL, &inputPort);
        MIDIOutputPortCreate(client, CFSTR("RTP test send"), &outputPort);
        OSStatus connectStatus = MIDIPortConnectSource(inputPort, source, NULL);
        if (connectStatus != noErr) {
            fprintf(stderr, "Unable to connect RTP source: %d\n", (int)connectStatus);
            return 4;
        }

        Byte storage[1024];
        MIDIPacketList *packetList = (MIDIPacketList *)storage;
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        UInt8 message[2] = {0xC0, expectedProgram};
        MIDIPacketListAdd(packetList, sizeof(storage), packet, 0, 2, message);
        sentAt = CFAbsoluteTimeGetCurrent();
        OSStatus sendStatus = MIDISend(outputPort, destination, packetList);
        fprintf(stdout, "SENT channel=1 program=%u scene=%lu status=%d\n",
                expectedProgram, (unsigned long)sceneNumber, (int)sendStatus);
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (!received && deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        MIDIPortDisconnectSource(inputPort, source);
        MIDIPortDispose(inputPort);
        MIDIPortDispose(outputPort);
        MIDIClientDispose(client);
        if (!received) {
            fprintf(stderr, "TIMEOUT scene=%lu timeout_s=%.1f\n", (unsigned long)sceneNumber, timeout);
            return 5;
        }
    }
    return 0;
}

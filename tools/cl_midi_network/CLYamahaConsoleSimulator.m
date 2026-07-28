#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <dispatch/dispatch.h>
#import <signal.h>

static MIDIPortRef outputPort = 0;
static MIDIEndpointRef networkDestination = 0;
static NSUInteger echoDelayMs = 80;
static BOOL echoEnabled = YES;
static NSString *consoleLabel = @"QL1";
static volatile sig_atomic_t keepRunning = 1;
static UInt8 lastSentStatus = 0;
static UInt8 lastSentProgram = 0;
static CFAbsoluteTime lastSentAt = 0;
static NSUInteger selfEchoBudget = 0;

static BOOL consumeSelfEcho(UInt8 status, UInt8 program) {
    @synchronized (consoleLabel) {
        CFAbsoluteTime age = CFAbsoluteTimeGetCurrent() - lastSentAt;
        if (selfEchoBudget > 0 && age >= 0 && age <= 0.5 &&
            status == lastSentStatus && program == lastSentProgram) {
            selfEchoBudget -= 1;
            fprintf(stdout, "IGNORED_SELF_ECHO console=%s channel=%u program=%u scene=%u\n",
                    consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1);
            fflush(stdout);
            return YES;
        }
        if (age > 0.5) selfEchoBudget = 0;
    }
    return NO;
}

static void stopHandler(int signalValue) {
    (void)signalValue;
    keepRunning = 0;
}

static NSString *argumentValue(NSArray<NSString *> *arguments, NSString *name, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:name];
    if (index != NSNotFound && index + 1 < arguments.count) return arguments[index + 1];
    return fallback;
}

static NSString *endpointName(MIDIEndpointRef endpoint) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || value == NULL) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    }
    return CFBridgingRelease(value) ?: @"";
}

static MIDIEndpointRef findEndpoint(BOOL source, NSString *preferredName) {
    ItemCount count = source ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
    MIDIEndpointRef fallback = 0;
    for (ItemCount index = 0; index < count; index++) {
        MIDIEndpointRef endpoint = source ? MIDIGetSource(index) : MIDIGetDestination(index);
        NSString *name = endpointName(endpoint);
        fprintf(stdout, "MIDI_%s index=%lu name=%s\n", source ? "SOURCE" : "DESTINATION",
                (unsigned long)index, name.UTF8String);
        if ([name rangeOfString:preferredName options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return endpoint;
        }
        if (fallback == 0 &&
            ([name rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound ||
             [name rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound ||
             [name rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
            fallback = endpoint;
        }
    }
    return fallback;
}

static void sendProgramChange(UInt8 status, UInt8 program) {
    Byte storage[1024];
    MIDIPacketList *packetList = (MIDIPacketList *)storage;
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    UInt8 bytes[2] = {status, program};
    packet = MIDIPacketListAdd(packetList, sizeof(storage), packet, 0, 2, bytes);
    if (packet != NULL && outputPort != 0 && networkDestination != 0) {
        @synchronized (consoleLabel) {
            lastSentStatus = status;
            lastSentProgram = program;
            lastSentAt = CFAbsoluteTimeGetCurrent();
            selfEchoBudget = 1;
        }
        OSStatus result = MIDISend(outputPort, networkDestination, packetList);
        if (result != noErr) {
            @synchronized (consoleLabel) { selfEchoBudget = 0; }
        }
        fprintf(stdout, "CONFIRMED console=%s channel=%u program=%u scene=%u status=%d\n",
                consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1, (int)result);
        fflush(stdout);
    }
}

static void midiRead(const MIDIPacketList *packetList, void *readProcRefCon, void *srcConnRefCon) {
    (void)readProcRefCon;
    (void)srcConnRefCon;
    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packetList->numPackets; packetIndex++) {
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 status = packet->data[index];
            if ((status & 0xF0) == 0xC0 && index + 1 < packet->length) {
                UInt8 program = packet->data[index + 1];
                if (consumeSelfEcho(status, program)) {
                    index += 2;
                    continue;
                }
                fprintf(stdout, "RECEIVED console=%s channel=%u program=%u scene=%u\n",
                        consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1);
                fflush(stdout);
                if (echoEnabled) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(echoDelayMs * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        sendProgramChange(status, program);
                    });
                }
                index += 2;
                continue;
            }
            index += 1;
        }
        packet = MIDIPacketNext(packet);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--help"]) {
            puts("Usage: CLYamahaConsoleSimulator [--label QL1] [--delay-ms 80] [--no-echo]");
            return 0;
        }
        consoleLabel = argumentValue(arguments, @"--label", @"QL1");
        NSString *endpointSearchName = argumentValue(arguments, @"--endpoint", @"mb pro");
        echoDelayMs = (NSUInteger)[argumentValue(arguments, @"--delay-ms", @"80") integerValue];
        echoEnabled = ![arguments containsObject:@"--no-echo"];
        signal(SIGINT, stopHandler);
        signal(SIGTERM, stopHandler);

        MIDINetworkSession *session = [MIDINetworkSession defaultSession];
        session.enabled = YES;
        session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
        MIDIEndpointRef networkSource = 0;
        for (NSUInteger attempt = 0; attempt < 50; attempt++) {
            networkSource = session.sourceEndpoint;
            networkDestination = session.destinationEndpoint;
            if (networkSource != 0 && networkDestination != 0) break;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        if (networkSource == 0) networkSource = findEndpoint(YES, endpointSearchName);
        if (networkDestination == 0) networkDestination = findEndpoint(NO, endpointSearchName);
        if (networkSource == 0 || networkDestination == 0) {
            fprintf(stderr, "RTP session endpoints unavailable source=%u destination=%u\n",
                    (unsigned int)networkSource, (unsigned int)networkDestination);
            return 1;
        }

        MIDIClientRef client = 0;
        MIDIPortRef inputPort = 0;
        OSStatus clientStatus = MIDIClientCreate(CFSTR("CL Yamaha Console Simulator"), NULL, NULL, &client);
        OSStatus inputStatus = MIDIInputPortCreate(client, CFSTR("RTP input"), midiRead, NULL, &inputPort);
        OSStatus outputStatus = MIDIOutputPortCreate(client, CFSTR("RTP confirmation"), &outputPort);
        OSStatus connectStatus = MIDIPortConnectSource(inputPort, networkSource, NULL);
        if (clientStatus || inputStatus || outputStatus || connectStatus) {
            fprintf(stderr, "CoreMIDI setup failed client=%d input=%d output=%d connect=%d\n",
                    (int)clientStatus, (int)inputStatus, (int)outputStatus, (int)connectStatus);
            return 1;
        }

        fprintf(stdout, "READY console=%s delay_ms=%lu echo=%s session=%s port=%lu\n",
                consoleLabel.UTF8String, (unsigned long)echoDelayMs,
                echoEnabled ? "on" : "off", session.localName.UTF8String,
                (unsigned long)session.networkPort);
        fflush(stdout);

        while (keepRunning) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        }
        MIDIPortDisconnectSource(inputPort, networkSource);
        MIDIPortDispose(inputPort);
        MIDIPortDispose(outputPort);
        MIDIClientDispose(client);
    }
    return 0;
}

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <dispatch/dispatch.h>
#import <signal.h>

static MIDIPortRef outputPort = 0;
static MIDIEndpointRef networkDestination = 0;
static NSUInteger echoDelayMs = 80;
static BOOL echoEnabled = YES;
static NSString *consoleLabel = @"QL1";
static NSUInteger acceptedChannel = 0;
static volatile sig_atomic_t keepRunning = 1;

// CoreMIDI does not expose the origin of a packet received from a network
// session. Keep a short history of our own confirmations so every reflected
// copy is discarded, even if another Program Change was sent in between.
typedef struct {
    UInt8 status;
    UInt8 program;
    CFAbsoluteTime sentAt;
} CLSentConfirmation;

enum {
    CLSentHistorySize = 64,
    CLMaxPendingConfirmations = 32,
    CLMaxReceivedPerSecond = 64
};

static CLSentConfirmation sentHistory[CLSentHistorySize];
static NSUInteger sentHistoryCursor = 0;
static BOOL pendingConfirmations[16][128];
static NSUInteger pendingConfirmationCount = 0;
static CFAbsoluteTime receiveWindowStartedAt = 0;
static NSUInteger receiveWindowCount = 0;
static CFAbsoluteTime echoMutedUntil = 0;

static void markConfirmationSent(UInt8 status, UInt8 program) {
    @synchronized (consoleLabel) {
        sentHistory[sentHistoryCursor].status = status;
        sentHistory[sentHistoryCursor].program = program;
        sentHistory[sentHistoryCursor].sentAt = CFAbsoluteTimeGetCurrent();
        sentHistoryCursor = (sentHistoryCursor + 1) % CLSentHistorySize;
    }
}

static BOOL consumeSelfEcho(UInt8 status, UInt8 program) {
    @synchronized (consoleLabel) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        for (NSUInteger index = 0; index < CLSentHistorySize; index++) {
            CFAbsoluteTime age = now - sentHistory[index].sentAt;
            if (sentHistory[index].sentAt > 0 && age >= 0 && age <= 2.0 &&
                status == sentHistory[index].status && program == sentHistory[index].program) {
                fprintf(stdout, "IGNORED_SELF_ECHO console=%s channel=%u program=%u scene=%u age_ms=%.1f\n",
                        consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1,
                        age * 1000.0);
                fflush(stdout);
                return YES;
            }
        }
    }
    return NO;
}

static BOOL reserveConfirmation(UInt8 status, UInt8 program) {
    NSUInteger channel = status & 0x0F;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (consoleLabel) {
        if (now < echoMutedUntil) return NO;
        if (receiveWindowStartedAt == 0 || now - receiveWindowStartedAt >= 1.0) {
            receiveWindowStartedAt = now;
            receiveWindowCount = 0;
        }
        receiveWindowCount += 1;
        if (receiveWindowCount > CLMaxReceivedPerSecond ||
            pendingConfirmationCount >= CLMaxPendingConfirmations) {
            echoMutedUntil = now + 2.0;
            fprintf(stderr, "ECHO_CIRCUIT_OPEN console=%s received_per_second=%lu pending=%lu mute_ms=2000\n",
                    consoleLabel.UTF8String, (unsigned long)receiveWindowCount,
                    (unsigned long)pendingConfirmationCount);
            fflush(stderr);
            return NO;
        }
        if (pendingConfirmations[channel][program]) {
            fprintf(stdout, "COALESCED_DUPLICATE console=%s channel=%lu program=%u scene=%u\n",
                    consoleLabel.UTF8String, (unsigned long)channel + 1, program, program + 1);
            fflush(stdout);
            return NO;
        }
        pendingConfirmations[channel][program] = YES;
        pendingConfirmationCount += 1;
        return YES;
    }
}

static BOOL releaseConfirmation(UInt8 status, UInt8 program) {
    NSUInteger channel = status & 0x0F;
    @synchronized (consoleLabel) {
        if (pendingConfirmations[channel][program]) {
            pendingConfirmations[channel][program] = NO;
            if (pendingConfirmationCount > 0) pendingConfirmationCount -= 1;
        }
        return CFAbsoluteTimeGetCurrent() >= echoMutedUntil;
    }
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
        markConfirmationSent(status, program);
        OSStatus result = MIDISend(outputPort, networkDestination, packetList);
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
                NSUInteger channel = (status & 0x0F) + 1;
                if (acceptedChannel > 0 && channel != acceptedChannel) {
                    index += 2;
                    continue;
                }
                if (consumeSelfEcho(status, program)) {
                    index += 2;
                    continue;
                }
                fprintf(stdout, "RECEIVED console=%s channel=%u program=%u scene=%u\n",
                        consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1);
                fflush(stdout);
                if (echoEnabled && reserveConfirmation(status, program)) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(echoDelayMs * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        if (releaseConfirmation(status, program)) {
                            sendProgramChange(status, program);
                        } else {
                            fprintf(stderr, "SUPPRESSED_PENDING_CONFIRMATION console=%s channel=%u program=%u scene=%u\n",
                                    consoleLabel.UTF8String, (status & 0x0F) + 1, program, program + 1);
                            fflush(stderr);
                        }
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
            puts("Usage: CLYamahaConsoleSimulator [--label QL1] [--endpoint name] [--channel 1-16] [--delay-ms 80] [--no-echo]");
            return 0;
        }
        consoleLabel = argumentValue(arguments, @"--label", @"QL1");
        NSString *endpointSearchName = argumentValue(arguments, @"--endpoint", @"mb pro");
        echoDelayMs = (NSUInteger)[argumentValue(arguments, @"--delay-ms", @"80") integerValue];
        acceptedChannel = (NSUInteger)[argumentValue(arguments, @"--channel", @"0") integerValue];
        if (acceptedChannel > 16) acceptedChannel = 0;
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

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <unistd.h>
#import <signal.h>
#import <time.h>

static volatile sig_atomic_t keepRunning = 1;

typedef struct {
    int controlFD;
    int dataFD;

    struct sockaddr_in remoteControl;
    struct sockaddr_in remoteData;

    uint32_t token;
    uint32_t ssrc;
    uint16_t sequence;

    struct timespec epoch;

    MIDIEndpointRef source;
    MIDIEndpointRef destination;

    BOOL ready;
} CLDirectState;

static void stopBridge(int value) {
    (void)value;
    keepRunning = 0;
}

static uint64_t clock10k(CLDirectState *state) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    int64_t sec = now.tv_sec - state->epoch.tv_sec;
    int64_t nsec = now.tv_nsec - state->epoch.tv_nsec;

    if (nsec < 0) {
        sec -= 1;
        nsec += 1000000000LL;
    }

    return (uint64_t)sec * 10000ULL + (uint64_t)nsec / 100000ULL;
}

static NSString *argumentValue(
    NSArray<NSString *> *arguments,
    NSString *name,
    NSString *fallback
) {
    NSUInteger index = [arguments indexOfObject:name];

    if (index != NSNotFound && index + 1 < arguments.count) {
        return arguments[index + 1];
    }

    return fallback;
}

static BOOL bindPair(CLDirectState *state) {
    for (uint16_t port = 54000; port < 56000; port += 2) {
        int controlFD = socket(AF_INET, SOCK_DGRAM, 0);
        int dataFD = socket(AF_INET, SOCK_DGRAM, 0);

        if (controlFD < 0 || dataFD < 0) {
            if (controlFD >= 0) close(controlFD);
            if (dataFD >= 0) close(dataFD);
            continue;
        }

        struct sockaddr_in controlAddress = {0};
        controlAddress.sin_len = sizeof(controlAddress);
        controlAddress.sin_family = AF_INET;
        controlAddress.sin_port = htons(port);
        controlAddress.sin_addr.s_addr = htonl(INADDR_ANY);

        struct sockaddr_in dataAddress = {0};
        dataAddress.sin_len = sizeof(dataAddress);
        dataAddress.sin_family = AF_INET;
        dataAddress.sin_port = htons(port + 1);
        dataAddress.sin_addr.s_addr = htonl(INADDR_ANY);

        if (
            bind(
                controlFD,
                (struct sockaddr *)&controlAddress,
                sizeof(controlAddress)
            ) == 0
            &&
            bind(
                dataFD,
                (struct sockaddr *)&dataAddress,
                sizeof(dataAddress)
            ) == 0
        ) {
            state->controlFD = controlFD;
            state->dataFD = dataFD;

            printf(
                "LOCAL control=%u data=%u\n",
                port,
                (uint16_t)(port + 1)
            );

            return YES;
        }

        close(controlFD);
        close(dataFD);
    }

    return NO;
}

static NSData *sessionPacket(
    CLDirectState *state,
    const char command[2],
    NSString *name
) {
    NSMutableData *data = [NSMutableData data];

    uint16_t signature = htons(0xFFFF);
    uint32_t version = htonl(2);
    uint32_t token = htonl(state->token);
    uint32_t ssrc = htonl(state->ssrc);

    [data appendBytes:&signature length:sizeof(signature)];
    [data appendBytes:command length:2];
    [data appendBytes:&version length:sizeof(version)];
    [data appendBytes:&token length:sizeof(token)];
    [data appendBytes:&ssrc length:sizeof(ssrc)];

    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];

    if (nameData.length) {
        [data appendData:nameData];
    }

    uint8_t zero = 0;
    [data appendBytes:&zero length:1];

    return data;
}

static NSData *ckPacket(
    CLDirectState *state,
    uint8_t count,
    uint64_t t1,
    uint64_t t2,
    uint64_t t3
) {
    NSMutableData *data = [NSMutableData data];

    uint16_t signature = htons(0xFFFF);
    uint32_t ssrc = htonl(state->ssrc);

    uint64_t n1 = CFSwapInt64HostToBig(t1);
    uint64_t n2 = CFSwapInt64HostToBig(t2);
    uint64_t n3 = CFSwapInt64HostToBig(t3);

    uint8_t reserved[3] = {0, 0, 0};

    [data appendBytes:&signature length:2];
    [data appendBytes:"CK" length:2];
    [data appendBytes:&ssrc length:4];
    [data appendBytes:&count length:1];
    [data appendBytes:reserved length:3];
    [data appendBytes:&n1 length:8];
    [data appendBytes:&n2 length:8];
    [data appendBytes:&n3 length:8];

    return data;
}

static BOOL waitReadable(int fd, double seconds) {
    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(fd, &readSet);

    struct timeval timeout;

    timeout.tv_sec = (int)seconds;
    timeout.tv_usec =
        (int)((seconds - timeout.tv_sec) * 1000000.0);

    int result = select(
        fd + 1,
        &readSet,
        NULL,
        NULL,
        &timeout
    );

    return result > 0 && FD_ISSET(fd, &readSet);
}

static BOOL parseOK(
    const uint8_t *buffer,
    ssize_t length,
    uint32_t token
) {
    if (length < 16) return NO;

    if (
        buffer[0] != 0xFF ||
        buffer[1] != 0xFF ||
        buffer[2] != 'O' ||
        buffer[3] != 'K'
    ) {
        return NO;
    }

    uint32_t receivedToken = 0;
    memcpy(&receivedToken, buffer + 8, 4);

    receivedToken = ntohl(receivedToken);

    return receivedToken == token;
}

static BOOL invite(
    CLDirectState *state,
    int fd,
    struct sockaddr_in *remote,
    NSString *name
) {
    NSData *packet = sessionPacket(
        state,
        "IN",
        name
    );

    sendto(
        fd,
        packet.bytes,
        packet.length,
        0,
        (struct sockaddr *)remote,
        sizeof(*remote)
    );

    if (!waitReadable(fd, 2.0)) {
        return NO;
    }

    uint8_t buffer[2048];

    ssize_t length = recv(
        fd,
        buffer,
        sizeof(buffer),
        0
    );

    return parseOK(
        buffer,
        length,
        state->token
    );
}

static BOOL parseCK(
    const uint8_t *buffer,
    ssize_t length,
    uint8_t *count,
    uint64_t *t1,
    uint64_t *t2,
    uint64_t *t3
) {
    if (length < 36) return NO;

    if (
        buffer[0] != 0xFF ||
        buffer[1] != 0xFF ||
        buffer[2] != 'C' ||
        buffer[3] != 'K'
    ) {
        return NO;
    }

    *count = buffer[8];

    uint64_t v1 = 0;
    uint64_t v2 = 0;
    uint64_t v3 = 0;

    memcpy(&v1, buffer + 12, 8);
    memcpy(&v2, buffer + 20, 8);
    memcpy(&v3, buffer + 28, 8);

    *t1 = CFSwapInt64BigToHost(v1);
    *t2 = CFSwapInt64BigToHost(v2);
    *t3 = CFSwapInt64BigToHost(v3);

    return YES;
}

static BOOL performCK(CLDirectState *state) {
    uint64_t localT1 = clock10k(state);

    NSData *start = ckPacket(
        state,
        0,
        localT1,
        0,
        0
    );

    sendto(
        state->dataFD,
        start.bytes,
        start.length,
        0,
        (struct sockaddr *)&state->remoteData,
        sizeof(state->remoteData)
    );

    double deadline =
        [[NSDate date] timeIntervalSince1970] + 0.8;

    while (
        [[NSDate date] timeIntervalSince1970] < deadline
    ) {
        if (!waitReadable(state->dataFD, 0.1)) {
            continue;
        }

        uint8_t buffer[4096];

        ssize_t length = recv(
            state->dataFD,
            buffer,
            sizeof(buffer),
            0
        );

        uint8_t count = 0;
        uint64_t t1 = 0;
        uint64_t t2 = 0;
        uint64_t t3 = 0;

        if (!parseCK(
            buffer,
            length,
            &count,
            &t1,
            &t2,
            &t3
        )) {
            continue;
        }

        if (
            count == 1 &&
            t1 == localT1
        ) {
            NSData *finish = ckPacket(
                state,
                2,
                t1,
                t2,
                clock10k(state)
            );

            sendto(
                state->dataFD,
                finish.bytes,
                finish.length,
                0,
                (struct sockaddr *)&state->remoteData,
                sizeof(state->remoteData)
            );

            return YES;
        }

        if (count == 0) {
            NSData *reply = ckPacket(
                state,
                1,
                t1,
                clock10k(state),
                0
            );

            sendto(
                state->dataFD,
                reply.bytes,
                reply.length,
                0,
                (struct sockaddr *)&state->remoteData,
                sizeof(state->remoteData)
            );
        }
    }

    return NO;
}

static void sendMIDI(
    CLDirectState *state,
    const uint8_t *bytes,
    NSUInteger length
) {
    if (
        !state->ready ||
        length == 0 ||
        length > 15
    ) {
        return;
    }

    uint8_t packet[64] = {0};

    packet[0] = 0x80;
    packet[1] = 0x61;

    uint16_t sequence = htons(state->sequence++);
    uint32_t timestamp =
        htonl((uint32_t)(clock10k(state) & 0xFFFFFFFF));
    uint32_t ssrc = htonl(state->ssrc);

    memcpy(packet + 2, &sequence, 2);
    memcpy(packet + 4, &timestamp, 4);
    memcpy(packet + 8, &ssrc, 4);

    packet[12] = (uint8_t)length;

    memcpy(
        packet + 13,
        bytes,
        length
    );

    sendto(
        state->dataFD,
        packet,
        13 + length,
        0,
        (struct sockaddr *)&state->remoteData,
        sizeof(state->remoteData)
    );
}

static void destinationReadProc(
    const MIDIPacketList *packetList,
    void *readProcRefCon,
    void *srcConnRefCon
) {
    (void)srcConnRefCon;

    CLDirectState *state =
        (CLDirectState *)readProcRefCon;

    const MIDIPacket *packet =
        &packetList->packet[0];

    for (
        UInt32 index = 0;
        index < packetList->numPackets;
        index++
    ) {
        if (packet->length > 0) {
            sendMIDI(
                state,
                packet->data,
                packet->length
            );
        }

        packet = MIDIPacketNext(packet);
    }
}

static NSUInteger midiDataLengthForStatus(uint8_t status) {
    uint8_t family = status & 0xF0;

    if (status < 0xF0) {
        if (family == 0xC0 || family == 0xD0) return 1;
        if (family >= 0x80 && family <= 0xE0) return 2;
        return 0;
    }

    switch (status) {
        case 0xF1: return 1;
        case 0xF2: return 2;
        case 0xF3: return 1;
        case 0xF6:
        case 0xF7:
        case 0xF8:
        case 0xF9:
        case 0xFA:
        case 0xFB:
        case 0xFC:
        case 0xFD:
        case 0xFE:
        case 0xFF:
            return 0;
        default:
            return 0;
    }
}

static BOOL skipRTPMIDIDelta(
    const uint8_t *bytes,
    NSUInteger length,
    NSUInteger *position
) {
    NSUInteger count = 0;

    while (*position < length && count < 4) {
        uint8_t byte = bytes[(*position)++];
        count++;

        if ((byte & 0x80) == 0) return YES;
    }

    return NO;
}

static NSData *decodeRTPMIDICommandList(
    const uint8_t *bytes,
    NSUInteger length,
    BOOL firstCommandHasDelta
) {
    NSMutableData *decoded = [NSMutableData data];
    NSUInteger position = 0;
    uint8_t runningStatus = 0;
    BOOL firstCommand = YES;

    if (firstCommandHasDelta) {
        if (!skipRTPMIDIDelta(bytes, length, &position)) return nil;
    }

    while (position < length) {
        uint8_t first = bytes[position];
        uint8_t status = 0;
        BOOL explicitStatus = (first & 0x80) != 0;

        if (explicitStatus) {
            status = first;
            position++;

            if (status >= 0xF8) {
                [decoded appendBytes:&status length:1];
            } else if (status == 0xF0) {
                [decoded appendBytes:&status length:1];

                BOOL ended = NO;
                while (position < length) {
                    uint8_t byte = bytes[position++];
                    [decoded appendBytes:&byte length:1];

                    if (byte == 0xF7) {
                        ended = YES;
                        break;
                    }
                }

                runningStatus = 0;

                if (!ended) return decoded;
            } else {
                if (status < 0xF0) {
                    runningStatus = status;
                } else {
                    runningStatus = 0;
                }

                NSUInteger needed = midiDataLengthForStatus(status);
                [decoded appendBytes:&status length:1];

                NSUInteger copied = 0;
                while (copied < needed && position < length) {
                    uint8_t byte = bytes[position];

                    if (byte >= 0xF8) {
                        position++;
                        [decoded appendBytes:&byte length:1];
                        continue;
                    }

                    if (byte & 0x80) return nil;

                    position++;
                    [decoded appendBytes:&byte length:1];
                    copied++;
                }

                if (copied != needed) return nil;
            }
        } else {
            if (runningStatus == 0) return nil;

            status = runningStatus;
            NSUInteger needed = midiDataLengthForStatus(status);
            [decoded appendBytes:&status length:1];

            NSUInteger copied = 0;
            while (copied < needed && position < length) {
                uint8_t byte = bytes[position];

                if (byte >= 0xF8) {
                    position++;
                    [decoded appendBytes:&byte length:1];
                    continue;
                }

                if (byte & 0x80) return nil;

                position++;
                [decoded appendBytes:&byte length:1];
                copied++;
            }

            if (copied != needed) return nil;
        }

        firstCommand = NO;

        if (position < length) {
            if (!skipRTPMIDIDelta(bytes, length, &position)) return nil;
        }
    }

    (void)firstCommand;
    return decoded;
}

static void deliverRTPMIDI(
    CLDirectState *state,
    const uint8_t *buffer,
    ssize_t length
) {
    if (length < 13) return;

    if (
        (buffer[0] >> 6) != 2 ||
        (buffer[1] & 0x7F) != 97
    ) {
        return;
    }

    const uint8_t *payload = buffer + 12;
    ssize_t payloadLength = length - 12;

    if (payloadLength < 1) return;

    uint8_t header = payload[0];
    NSUInteger commandLength = 0;
    NSUInteger offset = 1;

    if (header & 0x80) {
        if (payloadLength < 2) return;

        commandLength =
            ((NSUInteger)(header & 0x0F) << 8)
            |
            payload[1];

        offset = 2;
    } else {
        commandLength = header & 0x0F;
    }

    if (
        commandLength == 0 ||
        offset + commandLength >
            (NSUInteger)payloadLength
    ) {
        return;
    }

    BOOL firstCommandHasDelta = (header & 0x20) != 0;

    NSData *decoded = decodeRTPMIDICommandList(
        payload + offset,
        commandLength,
        firstCommandHasDelta
    );

    if (!decoded || decoded.length == 0 || decoded.length > UINT16_MAX) {
        return;
    }

    Byte packetBuffer[4096];

    MIDIPacketList *list =
        (MIDIPacketList *)packetBuffer;

    MIDIPacket *packet =
        MIDIPacketListInit(list);

    packet = MIDIPacketListAdd(
        list,
        sizeof(packetBuffer),
        packet,
        0,
        (UInt16)decoded.length,
        decoded.bytes
    );

    if (packet) {
        MIDIReceived(
            state->source,
            list
        );
    }
}

static void pollData(CLDirectState *state) {
    while (waitReadable(state->dataFD, 0.0)) {
        uint8_t buffer[4096];

        ssize_t length = recv(
            state->dataFD,
            buffer,
            sizeof(buffer),
            0
        );

        if (length <= 0) return;

        if (
            length >= 4 &&
            buffer[0] == 0xFF &&
            buffer[1] == 0xFF &&
            buffer[2] == 'C' &&
            buffer[3] == 'K'
        ) {
            uint8_t count = 0;
            uint64_t t1 = 0;
            uint64_t t2 = 0;
            uint64_t t3 = 0;

            if (
                parseCK(
                    buffer,
                    length,
                    &count,
                    &t1,
                    &t2,
                    &t3
                )
                &&
                count == 0
            ) {
                NSData *reply =
                    ckPacket(
                        state,
                        1,
                        t1,
                        clock10k(state),
                        0
                    );

                sendto(
                    state->dataFD,
                    reply.bytes,
                    reply.length,
                    0,
                    (struct sockaddr *)&state->remoteData,
                    sizeof(state->remoteData)
                );
            }

            continue;
        }

        if (
            length >= 2 &&
            buffer[0] == 0xFF &&
            buffer[1] == 0xFF
        ) {
            continue;
        }

        deliverRTPMIDI(
            state,
            buffer,
            length
        );
    }
}

static void sendBye(
    CLDirectState *state,
    NSString *name
) {
    NSData *packet = sessionPacket(
        state,
        "BY",
        name
    );

    sendto(
        state->controlFD,
        packet.bytes,
        packet.length,
        0,
        (struct sockaddr *)&state->remoteControl,
        sizeof(state->remoteControl)
    );

    sendto(
        state->dataFD,
        packet.bytes,
        packet.length,
        0,
        (struct sockaddr *)&state->remoteData,
        sizeof(state->remoteData)
    );
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments =
            NSProcessInfo.processInfo.arguments;

        NSString *host = argumentValue(
            arguments,
            @"--host",
            @"127.0.0.1"
        );

        uint16_t port =
            (uint16_t)[
                argumentValue(
                    arguments,
                    @"--port",
                    @"5006"
                )
                integerValue
            ];

        NSString *peerName =
            argumentValue(
                arguments,
                @"--peer-name",
                @"CL Ableton Distant"
            );

        NSString *endpointName =
            argumentValue(
                arguments,
                @"--endpoint",
                @"CL Direct RTP"
            );

        CLDirectState state = {0};

        state.controlFD = -1;
        state.dataFD = -1;

        arc4random_buf(
            &state.token,
            sizeof(state.token)
        );

        arc4random_buf(
            &state.ssrc,
            sizeof(state.ssrc)
        );

        arc4random_buf(
            &state.sequence,
            sizeof(state.sequence)
        );

        clock_gettime(
            CLOCK_MONOTONIC,
            &state.epoch
        );

        if (!bindPair(&state)) {
            fprintf(
                stderr,
                "DIRECT_BIND_FAILED\n"
            );
            return 2;
        }

        memset(
            &state.remoteControl,
            0,
            sizeof(state.remoteControl)
        );

        state.remoteControl.sin_len =
            sizeof(state.remoteControl);

        state.remoteControl.sin_family =
            AF_INET;

        state.remoteControl.sin_port =
            htons(port);

        if (
            inet_pton(
                AF_INET,
                host.UTF8String,
                &state.remoteControl.sin_addr
            ) != 1
        ) {
            fprintf(
                stderr,
                "INVALID_HOST %s\n",
                host.UTF8String
            );

            return 3;
        }

        state.remoteData =
            state.remoteControl;

        state.remoteData.sin_port =
            htons(port + 1);

        printf(
            "REMOTE host=%s control=%u data=%u\n",
            host.UTF8String,
            port,
            (uint16_t)(port + 1)
        );

        if (
            !invite(
                &state,
                state.controlFD,
                &state.remoteControl,
                endpointName
            )
        ) {
            fprintf(
                stderr,
                "CONTROL_INVITE_FAILED\n"
            );

            return 4;
        }

        printf("CONTROL_OK\n");

        if (
            !invite(
                &state,
                state.dataFD,
                &state.remoteData,
                endpointName
            )
        ) {
            fprintf(
                stderr,
                "DATA_INVITE_FAILED\n"
            );

            return 5;
        }

        printf("DATA_OK\n");

        NSUInteger completed = 0;

        for (
            NSUInteger index = 0;
            index < 5;
            index++
        ) {
            if (performCK(&state)) {
                completed += 1;
            }

            usleep(250000);
        }

        printf(
            "CK_READY completed=%lu/5\n",
            (unsigned long)completed
        );

        if (completed < 4) {
            fprintf(
                stderr,
                "CK_SYNC_FAILED\n"
            );

            sendBye(
                &state,
                endpointName
            );

            return 6;
        }

        MIDIClientRef client = 0;

        if (
            MIDIClientCreate(
                CFSTR("CL Direct RTP Bridge"),
                NULL,
                NULL,
                &client
            ) != noErr
        ) {
            fprintf(
                stderr,
                "MIDI_CLIENT_FAILED\n"
            );

            return 7;
        }

        if (
            MIDISourceCreate(
                client,
                (__bridge CFStringRef)endpointName,
                &state.source
            ) != noErr
        ) {
            fprintf(
                stderr,
                "MIDI_SOURCE_FAILED\n"
            );

            MIDIClientDispose(client);

            return 8;
        }

        if (
            MIDIDestinationCreate(
                client,
                (__bridge CFStringRef)endpointName,
                destinationReadProc,
                &state,
                &state.destination
            ) != noErr
        ) {
            fprintf(
                stderr,
                "MIDI_DESTINATION_FAILED\n"
            );

            MIDIEndpointDispose(
                state.source
            );

            MIDIClientDispose(client);

            return 9;
        }

        state.ready = YES;

        printf(
            "DIRECT_READY endpoint=%s peer=%s\n",
            endpointName.UTF8String,
            peerName.UTF8String
        );

        signal(
            SIGINT,
            stopBridge
        );

        signal(
            SIGTERM,
            stopBridge
        );

        double nextCK =
            [[NSDate date] timeIntervalSince1970]
            + 10.0;

        while (keepRunning) {
            pollData(&state);

            double now =
                [[NSDate date] timeIntervalSince1970];

            if (now >= nextCK) {
                performCK(&state);
                nextCK = now + 10.0;
            }

            usleep(5000);
        }

        state.ready = NO;

        sendBye(
            &state,
            endpointName
        );

        MIDIEndpointDispose(
            state.destination
        );

        MIDIEndpointDispose(
            state.source
        );

        MIDIClientDispose(client);

        close(state.controlFD);
        close(state.dataFD);
    }

    return 0;
}

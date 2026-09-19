#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/runtime.h>

#include <arpa/inet.h>
#include <math.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <mach/mach_time.h>

static const char *INPUT_NAME  = "Gestionnaire IAC Ableton Clock";
static const char *OUTPUT_NAME = "Gestionnaire IAC MTC vers Logic";

static const int ABSOLUTE_TIME_UDP_PORT = 20809;
static const double ABSOLUTE_LOCATE_THRESHOLD = 0.120;

static MIDIClientRef gClient = 0;
static MIDIPortRef gInputPort = 0;
static MIDIPortRef gOutputPort = 0;
static MIDIEndpointRef gInputSource = 0;
static MIDIEndpointRef gOutputDestination = 0;

static BOOL gRunning = NO;

static double gTempo = 120.0;
static double gPositionSeconds = 0.0;
static double gPlayStartPositionSeconds = 0.0;
static double gPlayStartedAt = 0.0;

static double gLastClockAt = 0.0;
static double gClockIntervalEMA = 0.0;

static BOOL gHasAbsoluteTime = NO;
static double gLastAbsoluteTimeAt = 0.0;

static int gQuarterFrameIndex = 0;
static double gQuarterFrameSnapshotSeconds = 0.0;
static BOOL gQuarterFrameSnapshotValid = NO;


static double monotonicSeconds(void)
{
    static mach_timebase_info_data_t timebase = {0, 0};

    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }

    uint64_t ticks = mach_continuous_time();

    return
        ((double)ticks *
         (double)timebase.numer /
         (double)timebase.denom)
        / 1000000000.0;
}

static NSString *endpointName(MIDIEndpointRef endpoint)
{
    CFStringRef name = NULL;
    MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name);

    if (!name) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name);
    }

    if (!name) return @"";

    return CFBridgingRelease(name);
}

static MIDIEndpointRef findSource(const char *wanted)
{
    NSString *target = [NSString stringWithUTF8String:wanted];

    ItemCount count = MIDIGetNumberOfSources();

    for (ItemCount i = 0; i < count; i++) {
        MIDIEndpointRef ep = MIDIGetSource(i);

        if ([[endpointName(ep) lowercaseString]
             isEqualToString:[target lowercaseString]]) {
            return ep;
        }
    }

    return 0;
}

static MIDIEndpointRef findDestination(const char *wanted)
{
    NSString *target = [NSString stringWithUTF8String:wanted];

    ItemCount count = MIDIGetNumberOfDestinations();

    for (ItemCount i = 0; i < count; i++) {
        MIDIEndpointRef ep = MIDIGetDestination(i);

        if ([[endpointName(ep) lowercaseString]
             isEqualToString:[target lowercaseString]]) {
            return ep;
        }
    }

    return 0;
}

static void sendBytes(const UInt8 *bytes, UInt16 length)
{
    Byte buffer[1024];

    MIDIPacketList *packetList = (MIDIPacketList *)buffer;
    MIDIPacket *packet = MIDIPacketListInit(packetList);

    packet = MIDIPacketListAdd(
        packetList,
        sizeof(buffer),
        packet,
        0,
        length,
        bytes
    );

    if (!packet) {
        fprintf(stderr, "Erreur création paquet MIDI\n");
        return;
    }

    OSStatus status = MIDISend(
        gOutputPort,
        gOutputDestination,
        packetList
    );

    if (status != noErr) {
        fprintf(stderr, "MIDISend erreur %d\n", (int)status);
    }
}

static double currentTimeSeconds(void)
{
    if (!gRunning) {
        return gPositionSeconds;
    }

    double now = monotonicSeconds();

    return
        gPlayStartPositionSeconds +
        (now - gPlayStartedAt);
}


static void secondsToTC(
    double seconds,
    int *hours,
    int *minutes,
    int *secs,
    int *frames
)
{
    if (seconds < 0) seconds = 0;

    long long totalFrames =
        llround(floor(seconds * 25.0));

    *frames = (int)(totalFrames % 25);

    long long totalSeconds = totalFrames / 25;

    *secs = (int)(totalSeconds % 60);
    *minutes = (int)((totalSeconds / 60) % 60);
    *hours = (int)((totalSeconds / 3600) % 24);
}

static double tcToSeconds(
    int hours,
    int minutes,
    int seconds,
    int frames
)
{
    return
        (hours * 3600.0) +
        (minutes * 60.0) +
        seconds +
        (frames / 25.0);
}

static void sendFullFrame(double seconds)
{
    int h, m, s, f;
    secondsToTC(seconds, &h, &m, &s, &f);

    UInt8 hourRate = (UInt8)(h | 0x20); // 25 fps

    UInt8 msg[] = {
        0xF0,
        0x7F,
        0x7F,
        0x01,
        0x01,
        hourRate,
        (UInt8)m,
        (UInt8)s,
        (UInt8)f,
        0xF7
    };

    sendBytes(msg, sizeof(msg));

    printf(
        "MTC FULL %02d:%02d:%02d:%02d\n",
        h, m, s, f
    );
}

static void sendQuarterFrame(void)
{
    if (
        gQuarterFrameIndex == 0 ||
        !gQuarterFrameSnapshotValid
    ) {
        gQuarterFrameSnapshotSeconds =
            currentTimeSeconds();

        gQuarterFrameSnapshotValid = YES;
    }

    int h, m, sec, f;

    secondsToTC(
        gQuarterFrameSnapshotSeconds,
        &h,
        &m,
        &sec,
        &f
    );

    UInt8 value = 0;

    switch (gQuarterFrameIndex) {

        case 0:
            value = (UInt8)(f & 0x0F);
            break;

        case 1:
            value = (UInt8)((f >> 4) & 0x01);
            break;

        case 2:
            value = (UInt8)(sec & 0x0F);
            break;

        case 3:
            value = (UInt8)((sec >> 4) & 0x03);
            break;

        case 4:
            value = (UInt8)(m & 0x0F);
            break;

        case 5:
            value = (UInt8)((m >> 4) & 0x03);
            break;

        case 6:
            value = (UInt8)(h & 0x0F);
            break;

        case 7:
            /*
                bits 1-2 = rate code.
                01 = 25 fps.
            */
            value =
                (UInt8)(
                    ((h >> 4) & 0x01) |
                    0x02
                );
            break;
    }

    UInt8 msg[] = {
        0xF1,
        (UInt8)(
            (gQuarterFrameIndex << 4) |
            value
        )
    };

    sendBytes(msg, 2);

    gQuarterFrameIndex++;

    if (gQuarterFrameIndex >= 8) {
        gQuarterFrameIndex = 0;
        gQuarterFrameSnapshotValid = NO;
    }
}


static BOOL absoluteTimeFresh(void)
{
    if (!gHasAbsoluteTime) {
        return NO;
    }

    return
        (monotonicSeconds() -
         gLastAbsoluteTimeAt)
        < 1.0;
}


static void setAbsoluteTime(
    int h,
    int m,
    int sec,
    int f
)
{
    if (
        h < 0 || h > 23 ||
        m < 0 || m > 59 ||
        sec < 0 || sec > 59 ||
        f < 0 || f > 24
    ) {
        return;
    }

    const double newSeconds =
        tcToSeconds(h, m, sec, f);

    const double now =
        monotonicSeconds();

    const double before =
        currentTimeSeconds();

    const double error =
        newSeconds - before;

    const BOOL firstAbsolute =
        !gHasAbsoluteTime;

    gHasAbsoluteTime = YES;
    gLastAbsoluteTimeAt = now;

    /*
        A L'ARRET :
        Max donne notre position absolue de référence.
    */
    if (!gRunning) {

        const BOOL moved =
            firstAbsolute ||
            fabs(newSeconds - gPositionSeconds)
                > 0.020;

        gPositionSeconds =
            newSeconds;

        gPlayStartPositionSeconds =
            newSeconds;

        if (moved) {

            printf(
                "ABS LOCATE %02d:%02d:%02d:%02d"
                " [STOP]\n",
                h, m, sec, f
            );

            sendFullFrame(newSeconds);

            gQuarterFrameIndex = 0;
            gQuarterFrameSnapshotValid = NO;
        }

        return;
    }

    /*
        EN LECTURE :
        Le timecode local est notre horloge maître entre
        deux vrais repositionnements.

        On ne suit PAS les +/- 40 ms de quantification et
        de jitter du Live API.
    */

    if (
        firstAbsolute ||
        fabs(error) >
            ABSOLUTE_LOCATE_THRESHOLD
    ) {

        gPositionSeconds =
            newSeconds;

        gPlayStartPositionSeconds =
            newSeconds;

        gPlayStartedAt = now;

        printf(
            "ABS LOCATE %02d:%02d:%02d:%02d"
            " correction=%+.3f s\n",
            h, m, sec, f, error
        );

        sendFullFrame(newSeconds);

        gQuarterFrameIndex = 0;
        gQuarterFrameSnapshotValid = NO;
    }
}


static BOOL parseTimecodeString(
    const char *text,
    int *h,
    int *m,
    int *s,
    int *f
)
{
    int hh = -1;
    int mm = -1;
    int ss = -1;
    int ff = 0;

    if (
        sscanf(
            text,
            "%d:%d:%d:%d",
            &hh, &mm, &ss, &ff
        ) == 4
    ) {
        *h = hh;
        *m = mm;
        *s = ss;
        *f = ff;
        return YES;
    }

    double fractionalSeconds = 0.0;

    if (
        sscanf(
            text,
            "%d:%d:%lf",
            &hh, &mm, &fractionalSeconds
        ) == 3
    ) {
        ss = (int)floor(fractionalSeconds);

        double fraction =
            fractionalSeconds - ss;

        ff = (int)floor(
            fraction * 25.0 + 0.5
        );

        if (ff >= 25) {
            ff = 0;
            ss++;

            if (ss >= 60) {
                ss = 0;
                mm++;

                if (mm >= 60) {
                    mm = 0;
                    hh++;
                }
            }
        }

        *h = hh;
        *m = mm;
        *s = ss;
        *f = ff;

        return YES;
    }

    return NO;
}

/*
    Les messages de Max udpsend sont sérialisés dans le
    paquet UDP. On cherche donc toute chaîne ASCII qui
    ressemble à HH:MM:SS:FF ou HH:MM:SS.xxx.
*/
static BOOL extractTimecodeFromUDP(
    const unsigned char *data,
    ssize_t length,
    int *h,
    int *m,
    int *s,
    int *f
)
{
    char candidate[128];

    for (ssize_t start = 0; start < length; start++) {

        if (
            data[start] < '0' ||
            data[start] > '9'
        ) {
            continue;
        }

        size_t n = 0;

        for (
            ssize_t i = start;
            i < length &&
            n < sizeof(candidate) - 1;
            i++
        ) {
            unsigned char c = data[i];

            if (
                (c >= '0' && c <= '9') ||
                c == ':' ||
                c == '.'
            ) {
                candidate[n++] = (char)c;
            } else {
                break;
            }
        }

        candidate[n] = '\0';

        int colonCount = 0;

        for (size_t j = 0; j < n; j++) {
            if (candidate[j] == ':') {
                colonCount++;
            }
        }

        if (
            colonCount >= 2 &&
            parseTimecodeString(
                candidate,
                h, m, s, f
            )
        ) {
            return YES;
        }
    }

    return NO;
}

static int setupAbsoluteTimeUDP(void)
{
    int fd = socket(
        AF_INET,
        SOCK_DGRAM,
        0
    );

    if (fd < 0) {
        perror("socket UDP");
        return -1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));

    addr.sin_family = AF_INET;
    addr.sin_port =
        htons(ABSOLUTE_TIME_UDP_PORT);

    addr.sin_addr.s_addr =
        htonl(INADDR_LOOPBACK);

    if (
        bind(
            fd,
            (struct sockaddr *)&addr,
            sizeof(addr)
        ) < 0
    ) {
        perror("bind UDP");
        close(fd);
        return -1;
    }

    dispatch_source_t source =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_READ,
            fd,
            0,
            dispatch_get_main_queue()
        );

    dispatch_source_set_event_handler(
        source,
        ^{
            unsigned char buffer[2048];

            ssize_t received =
                recv(
                    fd,
                    buffer,
                    sizeof(buffer),
                    0
                );

            if (received <= 0) {
                return;
            }

            int h, m, s, f;

            if (
                extractTimecodeFromUDP(
                    buffer,
                    received,
                    &h, &m, &s, &f
                )
            ) {
                setAbsoluteTime(
                    h, m, s, f
                );
            }
        }
    );

    dispatch_source_set_cancel_handler(
        source,
        ^{
            close(fd);
        }
    );

    dispatch_resume(source);

    /*
        Garde une référence forte au dispatch source.
    */
    objc_setAssociatedObject(
        [NSProcessInfo processInfo],
        "CLAbsoluteTimeUDP",
        source,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    return fd;
}

static void setSongPosition(UInt16 spp)
{
    /*
        SPP reste disponible uniquement comme secours.
        Dès que Max fournit une vraie position SMPTE,
        on ne l'utilise plus comme position absolue.
    */

    if (absoluteTimeFresh()) {
        return;
    }

    double secondsPerQuarter =
        60.0 / gTempo;

    double secondsPerSPP =
        secondsPerQuarter / 4.0;

    gPositionSeconds =
        spp * secondsPerSPP;

    if (gRunning) {
        gPlayStartPositionSeconds =
            gPositionSeconds;

        gPlayStartedAt =
            monotonicSeconds();
    }

    printf(
        "SPP FALLBACK %u -> %.3f s"
        " (tempo %.3f BPM)\n",
        spp,
        gPositionSeconds,
        gTempo
    );

    sendFullFrame(gPositionSeconds);
}

static void handleClock(void)
{
    double now =
        monotonicSeconds();

    if (gLastClockAt > 0) {

        double dt =
            now - gLastClockAt;

        if (
            dt > 0.005 &&
            dt < 0.200
        ) {
            if (gClockIntervalEMA <= 0) {
                gClockIntervalEMA = dt;
            } else {
                gClockIntervalEMA =
                    (gClockIntervalEMA * 0.90) +
                    (dt * 0.10);
            }

            double bpm =
                60.0 /
                (gClockIntervalEMA * 24.0);

            if (
                bpm > 20 &&
                bpm < 400
            ) {
                gTempo = bpm;
            }
        }
    }

    gLastClockAt = now;
}


static void handleStart(void)
{
    /*
        Si Max vient de nous donner une vraie position,
        FA ne remet PAS le TC à zéro.
    */
    if (!absoluteTimeFresh()) {
        gPositionSeconds = 0.0;
    }

    gRunning = YES;

    gPlayStartPositionSeconds =
        gPositionSeconds;

    gPlayStartedAt =
        monotonicSeconds();

    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;

    printf(
        "START %.3f s%s\n",
        gPositionSeconds,
        absoluteTimeFresh()
            ? " [ABS]"
            : " [FALLBACK]"
    );

    sendFullFrame(
        gPositionSeconds
    );
}


static void handleContinue(void)
{
    gRunning = YES;

    gPlayStartPositionSeconds =
        gPositionSeconds;

    gPlayStartedAt =
        monotonicSeconds();

    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;

    printf(
        "CONTINUE %.3f s%s\n",
        gPositionSeconds,
        absoluteTimeFresh()
            ? " [ABS]"
            : " [FALLBACK]"
    );

    sendFullFrame(
        gPositionSeconds
    );
}


static void handleStop(void)
{
    if (gRunning) {
        gPositionSeconds =
            currentTimeSeconds();
    }

    gRunning = NO;

    gPlayStartPositionSeconds =
        gPositionSeconds;

    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;

    printf(
        "STOP %.3f s\n",
        gPositionSeconds
    );

    sendFullFrame(
        gPositionSeconds
    );
}


static void parsePacket(
    const UInt8 *data,
    UInt16 length
)
{
    UInt16 i = 0;

    while (i < length) {

        UInt8 status = data[i];

        if (status == 0xF8) {
            handleClock();
            i++;
            continue;
        }

        if (status == 0xFA) {
            handleStart();
            i++;
            continue;
        }

        if (status == 0xFB) {
            handleContinue();
            i++;
            continue;
        }

        if (status == 0xFC) {
            handleStop();
            i++;
            continue;
        }

        if (
            status == 0xF2 &&
            i + 2 < length
        ) {
            UInt8 lsb =
                data[i + 1] & 0x7F;

            UInt8 msb =
                data[i + 2] & 0x7F;

            UInt16 spp =
                (UInt16)(
                    lsb |
                    (msb << 7)
                );

            setSongPosition(spp);

            i += 3;
            continue;
        }

        i++;
    }
}

static void midiRead(
    const MIDIPacketList *packetList,
    void *readProcRefCon,
    void *srcConnRefCon
)
{
    const MIDIPacket *packet =
        &packetList->packet[0];

    for (
        UInt32 i = 0;
        i < packetList->numPackets;
        i++
    ) {
        parsePacket(
            packet->data,
            packet->length
        );

        packet =
            MIDIPacketNext(packet);
    }
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {

        printf("\n");
        printf("========================================\n");
        printf(" CL ABLETON -> MTC BRIDGE V2\n");
        printf(" MTC 25 fps / position absolue Live API\n");
        printf("========================================\n\n");

        OSStatus status =
            MIDIClientCreate(
                CFSTR("CL Ableton MTC Bridge"),
                NULL,
                NULL,
                &gClient
            );

        if (status != noErr) {
            fprintf(
                stderr,
                "MIDIClientCreate erreur %d\n",
                (int)status
            );
            return 1;
        }

        gInputSource =
            findSource(INPUT_NAME);

        gOutputDestination =
            findDestination(OUTPUT_NAME);

        if (!gInputSource) {
            fprintf(
                stderr,
                "Entrée introuvable : %s\n",
                INPUT_NAME
            );
            return 2;
        }

        if (!gOutputDestination) {
            fprintf(
                stderr,
                "Sortie introuvable : %s\n",
                OUTPUT_NAME
            );
            return 3;
        }

        status =
            MIDIInputPortCreate(
                gClient,
                CFSTR("Ableton Clock Input"),
                midiRead,
                NULL,
                &gInputPort
            );

        if (status != noErr) {
            fprintf(
                stderr,
                "MIDIInputPortCreate erreur %d\n",
                (int)status
            );
            return 4;
        }

        status =
            MIDIOutputPortCreate(
                gClient,
                CFSTR("MTC Output"),
                &gOutputPort
            );

        if (status != noErr) {
            fprintf(
                stderr,
                "MIDIOutputPortCreate erreur %d\n",
                (int)status
            );
            return 5;
        }

        status =
            MIDIPortConnectSource(
                gInputPort,
                gInputSource,
                NULL
            );

        if (status != noErr) {
            fprintf(
                stderr,
                "MIDIPortConnectSource erreur %d\n",
                (int)status
            );
            return 6;
        }

        if (setupAbsoluteTimeUDP() < 0) {
            fprintf(
                stderr,
                "Impossible d'ouvrir UDP localhost:%d\n",
                ABSOLUTE_TIME_UDP_PORT
            );
            return 7;
        }

        dispatch_source_t timer =
            dispatch_source_create(
                DISPATCH_SOURCE_TYPE_TIMER,
                0,
                0,
                dispatch_get_main_queue()
            );

        dispatch_source_set_timer(
            timer,
            dispatch_time(
                DISPATCH_TIME_NOW,
                10 * NSEC_PER_MSEC
            ),
            10 * NSEC_PER_MSEC,
            200 * NSEC_PER_USEC
        );

        dispatch_source_set_event_handler(
            timer,
            ^{
                if (gRunning) {
                    sendQuarterFrame();
                }
            }
        );

        dispatch_resume(timer);

        printf(
            "ENTREE MIDI : %s\n",
            INPUT_NAME
        );

        printf(
            "SORTIE MTC  : %s\n",
            OUTPUT_NAME
        );

        printf(
            "LIVE API    : UDP localhost:%d\n",
            ABSOLUTE_TIME_UDP_PORT
        );

        printf("\nBridge prêt.\n");
        printf("Ctrl+C pour arrêter.\n\n");

        CFRunLoopRun();
    }

    return 0;
}

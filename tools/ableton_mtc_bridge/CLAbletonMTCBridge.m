#import "../shared/CLMIDIEndpointNames.h"
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/runtime.h>

#include <arpa/inet.h>
#include <math.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <mach/mach_time.h>

static const char *INPUT_NAME  = CL_MIDI_CLOCK_IAC;
static const char *OUTPUT_NAME = CL_MIDI_MTC_IAC;

static const int ABSOLUTE_TIME_UDP_PORT = 20809;

/*
    Flux diagnostic CL Sync.
    V1 : localhost uniquement.
    Ce flux n'intervient jamais dans la génération MTC.
*/
static const int SYNC_REF_UDP_PORT = 20810;
/* Quantification Live à 40 ms : confirmer un écart, jamais suivre le jitter. */
static const double ABSOLUTE_DRIFT_THRESHOLD = 0.200;
static const double ABSOLUTE_LOCATE_THRESHOLD = 0.500;
static unsigned gAbsoluteCandidateCount = 0;
static double gAbsoluteCandidateError = 0, gAbsoluteCandidateSince = 0;
static double gAbsoluteCandidateLastAt = 0, gLastDriftLogAt = -5.0;

static void resetAbsoluteCandidate(void)
{
    gAbsoluteCandidateCount = 0;
}

static MIDIClientRef gClient = 0;
static MIDIPortRef gInputPort = 0;
static MIDIPortRef gOutputPort = 0;
static MIDIEndpointRef gInputSource = 0;
static MIDIEndpointRef gOutputDestination = 0;

static BOOL gRunning = NO;

static int gSyncRefSocket = -1;
static struct sockaddr_in gSyncRefAddress;
static struct sockaddr_in gSyncRefRemoteAddress;
static BOOL gSyncRefRemoteEnabled = NO;
static uint64_t gSyncInstance = 0;
static double gLastAbsoluteRawSeconds = 0;
static BOOL absoluteTimeFresh(void);
static uint64_t gSyncRefSequence = 0;
static double gLastSyncRefAt = 0.0;

static double gTempo = 120.0;
static double gPositionSeconds = 0.0;
static double gPlayStartPositionSeconds = 0.0;
static double gPlayStartedAt = 0.0;
/* Décalage de position uniquement : l'horloge et le transport restent intacts. */
static double gMTCOffsetSeconds = 0.0;

static double gLastClockAt = 0.0;
static double gClockIntervalEMA = 0.0;

static BOOL gHasAbsoluteTime = NO;
static double gLastAbsoluteTimeAt = 0.0;

static int gQuarterFrameIndex = 0;
static double gQuarterFrameSnapshotSeconds = 0.0;
static BOOL gQuarterFrameSnapshotValid = NO;
static double gDiagnosticSnapshotMono = 0;
static uint64_t gDiagnosticCycle = 0;
static uint64_t gDiagnosticEpoch = 1, gDiagnosticSnapshotEpoch = 0;
static double gDiagnosticQF0Send = 0, gDiagnosticOffset = 0;


static double monotonicSeconds(void)
{
#ifdef CL_MTC_BRIDGE_TEST
    extern double clTestNow;
    return clTestNow;
#endif
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
    return CLMIDIFindEndpoint(YES, [NSString stringWithUTF8String:wanted]);
}

static MIDIEndpointRef findDestination(const char *wanted)
{
    return CLMIDIFindEndpoint(NO, [NSString stringWithUTF8String:wanted]);
}

static void sendBytes(const UInt8 *bytes, UInt16 length)
{
#ifdef CL_MTC_BRIDGE_TEST
    extern void clTestSend(const UInt8 *, UInt16);
    clTestSend(bytes, length);
    return;
#endif
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



/*
    Initialise uniquement la SORTIE UDP diagnostic.
    Aucun bind : le bridge reste seul propriétaire de 20809.
*/
static int setupSyncRefUDP(void)
{
    gSyncRefSocket =
        socket(
            AF_INET,
            SOCK_DGRAM,
            0
        );

    if (gSyncRefSocket < 0) {
        perror("socket CL Sync Ref");
        return -1;
    }

    memset(
        &gSyncRefAddress,
        0,
        sizeof(gSyncRefAddress)
    );

    gSyncRefAddress.sin_family =
        AF_INET;

    gSyncRefAddress.sin_port =
        htons(SYNC_REF_UDP_PORT);

    gSyncRefAddress.sin_addr.s_addr =
        htonl(INADDR_LOOPBACK);

    /*
        Destination réseau facultative pour le futur Remote MTC Bridge.
        Le localhost reste toujours actif pour CL Sync Meter.
    */
    const char *remoteIP =
        getenv("CL_SYNC_REMOTE_IP");

    if (remoteIP && remoteIP[0]) {
        memset(
            &gSyncRefRemoteAddress,
            0,
            sizeof(gSyncRefRemoteAddress)
        );

        gSyncRefRemoteAddress.sin_family =
            AF_INET;

        gSyncRefRemoteAddress.sin_port =
            htons(SYNC_REF_UDP_PORT);

        if (
            inet_pton(
                AF_INET,
                remoteIP,
                &gSyncRefRemoteAddress.sin_addr
            ) == 1
        ) {
            gSyncRefRemoteEnabled = YES;

            printf(
                "CL Sync Remote : UDP %s:%d\n",
                remoteIP,
                SYNC_REF_UDP_PORT
            );
        } else {
            fprintf(
                stderr,
                "CL Sync Remote : IP invalide '%s' — distant désactivé\n",
                remoteIP
            );
        }
    }

    return 0;
}


static void sendSyncReference(void)
{
    if (gSyncRefSocket < 0) {
        return;
    }

    const double now =
        monotonicSeconds();

    /*
        50 Hz suffisent largement pour la mesure.
        La génération MTC reste, elle, inchangée à 10 ms/QF.
    */
    if (
        gLastSyncRefAt > 0.0 &&
        (now - gLastSyncRefAt) < 0.020
    ) {
        return;
    }

    gLastSyncRefAt = now;

    if (!gSyncInstance) { arc4random_buf(&gSyncInstance, sizeof(gSyncInstance)); if (!gSyncInstance) gSyncInstance=1; }
    const double bridgeSeconds = currentTimeSeconds();
    double intendedMTCSeconds =
        bridgeSeconds +
        gMTCOffsetSeconds;

    while (intendedMTCSeconds < 0.0) {
        intendedMTCSeconds += 86400.0;
    }

    while (intendedMTCSeconds >= 86400.0) {
        intendedMTCSeconds -= 86400.0;
    }

    char packet[512];

    int length =
        snprintf(
            packet,
            sizeof(packet),
            "CLSYNC2 %llu %llx %.9f %.9f %.9f %.6f %d %d %.9f %d 25 %.9f\n",
            (unsigned long long)(++gSyncRefSequence),
            (unsigned long long)gSyncInstance,
            gLastAbsoluteRawSeconds,
            fmod(fmod(bridgeSeconds,86400.0)+86400.0,86400.0),
            intendedMTCSeconds, gMTCOffsetSeconds * 1000.0,
            gHasAbsoluteTime ? 1 : 0, absoluteTimeFresh() ? 1 : 0,
            gHasAbsoluteTime ? fmax(0.0,now-gLastAbsoluteTimeAt) : 0.0,
            gRunning ? 1 : 0, now
        );

    if (
        length <= 0 ||
        length >= (int)sizeof(packet)
    ) {
        return;
    }

    /*
        Copie locale : utilisée par CL Sync Meter.
    */
    sendto(
        gSyncRefSocket,
        packet,
        (size_t)length,
        MSG_DONTWAIT,
        (struct sockaddr *)&gSyncRefAddress,
        sizeof(gSyncRefAddress)
    );

    /*
        Copie réseau facultative.
        Le réseau transporte une référence de temps, pas les Quarter Frames.
    */
    if (gSyncRefRemoteEnabled) {
        sendto(
            gSyncRefSocket,
            packet,
            (size_t)length,
            MSG_DONTWAIT,
            (struct sockaddr *)&gSyncRefRemoteAddress,
            sizeof(gSyncRefRemoteAddress)
        );
    }
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
    ++gDiagnosticEpoch;
    if (gSyncRefSocket>=0 && gSyncInstance) {
        char boundary[160];
        int n=snprintf(boundary,sizeof(boundary),"CLSYNCB1 %llx %llu %.9f %.6f %d\n",
            (unsigned long long)gSyncInstance,(unsigned long long)gDiagnosticEpoch,
            monotonicSeconds(),gMTCOffsetSeconds*1000.0,gRunning?1:0);
        if (n>0 && n<(int)sizeof(boundary)) sendto(gSyncRefSocket,boundary,(size_t)n,MSG_DONTWAIT,
            (struct sockaddr *)&gSyncRefAddress,sizeof(gSyncRefAddress));
    }
    int h, m, s, f;
    secondsToTC(seconds + gMTCOffsetSeconds, &h, &m, &s, &f);

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
    if (!gRunning) return;
    if (
        gQuarterFrameIndex == 0 ||
        !gQuarterFrameSnapshotValid
    ) {
        gQuarterFrameSnapshotSeconds =
            currentTimeSeconds();
        gDiagnosticSnapshotMono = monotonicSeconds();
        ++gDiagnosticCycle;
        gDiagnosticSnapshotEpoch=gDiagnosticEpoch;
        gDiagnosticOffset=gMTCOffsetSeconds;

        gQuarterFrameSnapshotValid = YES;
    }

    int h, m, sec, f;

    secondsToTC(
        gQuarterFrameSnapshotSeconds + gMTCOffsetSeconds,
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

    // Diagnostic only: no change to MIDI bytes, schedule or offset.
    const double diagnosticEnd = monotonicSeconds();
    if (gQuarterFrameIndex==0) gDiagnosticQF0Send=diagnosticEnd;
    sendBytes(msg, 2);
    if (gQuarterFrameIndex == 7 && gSyncRefSocket >= 0 && gSyncInstance
        && gDiagnosticSnapshotEpoch==gDiagnosticEpoch && gDiagnosticOffset==gMTCOffsetSeconds) {
        char diagnostic[256];
        int n=snprintf(diagnostic,sizeof(diagnostic),
            "CLSYNCQ2 %llx %llu %llu %.9f %.9f %.9f %.9f %.9f %.6f\n",
            (unsigned long long)gSyncInstance,(unsigned long long)gDiagnosticEpoch,(unsigned long long)gDiagnosticCycle,
            tcToSeconds(h,m,sec,f),
            fmod(fmod(gQuarterFrameSnapshotSeconds+gMTCOffsetSeconds,86400.0)+86400.0,86400.0),
            gDiagnosticSnapshotMono,gDiagnosticQF0Send,diagnosticEnd,gDiagnosticOffset*1000.0);
        if (n>0 && n<(int)sizeof(diagnostic))
            sendto(gSyncRefSocket,diagnostic,(size_t)n,MSG_DONTWAIT,
                (struct sockaddr *)&gSyncRefAddress,sizeof(gSyncRefAddress));
    }

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

    /* SMPTE reboucle à 24 h : ne pas confondre minuit et un locate. */
    const double error = remainder(newSeconds - before, 86400.0);

    const BOOL firstAbsolute =
        !gHasAbsoluteTime;

    gHasAbsoluteTime = YES;
    gLastAbsoluteTimeAt = now;
    gLastAbsoluteRawSeconds = newSeconds;

    /*
        A L'ARRET :
        Max donne notre position absolue de référence.
    */
    if (!gRunning) {
        resetAbsoluteCandidate();

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

    /* Référence locale inchangée tant que plusieurs ABS ne concordent pas.
       Grand saut : 2 mesures / >=30 ms (normalement 40 ms).
       Dérive moyenne : 6 mesures / >=200 ms.
       Une interruption >200 ms ou une incohérence relance la confirmation. */
    if (fabs(error) < ABSOLUTE_DRIFT_THRESHOLD) {
        resetAbsoluteCandidate();
        if (fabs(error) >= 0.040 && now - gLastDriftLogAt >= 5.0) {
            printf("ABS DRIFT %+.3f s ignored\n", error);
            gLastDriftLogAt = now;
        }
        return;
    }

    if (!gAbsoluteCandidateCount ||
        now - gAbsoluteCandidateLastAt > 0.200 ||
        error * gAbsoluteCandidateError <= 0 ||
        fabs(error - gAbsoluteCandidateError) > 0.120 ||
        (fabs(error) > ABSOLUTE_LOCATE_THRESHOLD) !=
            (fabs(gAbsoluteCandidateError) > ABSOLUTE_LOCATE_THRESHOLD)) {
        gAbsoluteCandidateCount = 1;
        gAbsoluteCandidateSince = now;
        gAbsoluteCandidateError = error;
    } else {
        ++gAbsoluteCandidateCount;
    }
    gAbsoluteCandidateLastAt = now;

    const BOOL large = fabs(error) > ABSOLUTE_LOCATE_THRESHOLD;
    if (gAbsoluteCandidateCount < (large ? 2u : 6u) ||
        now - gAbsoluteCandidateSince + 1e-9 < (large ? 0.030 : 0.200)) {
        return;
    }

    gPositionSeconds = newSeconds;
    gPlayStartPositionSeconds = newSeconds;
    gPlayStartedAt = now;
    resetAbsoluteCandidate();
    printf("ABS LOCATE confirmed %+.3f s %02d:%02d:%02d:%02d\n",
           error, h, m, sec, f);
    sendFullFrame(newSeconds);
    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;
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

/* Commande dédiée du device, distincte des positions SMPTE historiques. */

static BOOL extractOffsetFromUDP(
    const unsigned char *data,
    ssize_t length,
    double *offset
)
{
    /* Ancien format texte : "CLMTC_OFFSET 50.0" */
    const char textPrefix[] = "CLMTC_OFFSET ";
    const size_t textPrefixLength = sizeof(textPrefix) - 1;

    for (ssize_t i = 0; i + (ssize_t)textPrefixLength < length; i++) {
        if (memcmp(data + i, textPrefix, textPrefixLength) != 0) continue;

        char number[32];
        size_t n = 0;

        for (
            ssize_t j = i + (ssize_t)textPrefixLength;
            j < length && n < sizeof(number) - 1;
            j++
        ) {
            unsigned char c = data[j];

            if (
                (c >= '0' && c <= '9') ||
                c == '-' ||
                c == '+' ||
                c == '.'
            ) {
                number[n++] = (char)c;
            } else {
                break;
            }
        }

        number[n] = '\0';

        char *end = NULL;
        double value = strtod(number, &end);

        if (
            n &&
            end == number + n &&
            isfinite(value) &&
            value >= -100.0 &&
            value <= 100.0
        ) {
            *offset = value / 1000.0;
            return YES;
        }
    }

    /*
        Format OSC emis par Max :
        adresse "CLMTC_OFFSET"
        typetag ",f"
        float32 big-endian
    */
    const char oscAddress[] = "CLMTC_OFFSET";
    const size_t addressLength = sizeof(oscAddress) - 1;

    for (ssize_t i = 0; i + (ssize_t)addressLength < length; i++) {
        if (memcmp(data + i, oscAddress, addressLength) != 0) continue;

        ssize_t p0 = i + (ssize_t)addressLength;

        /* Fin de l'adresse OSC puis padding 4 octets relatif au debut du paquet. */
        while (p0 < length && data[p0] != '\0') p0++;
        if (p0 >= length) continue;
        p0++;

        while ((p0 % 4) != 0 && p0 < length) p0++;
        if (p0 + 4 > length) continue;

        if (
            data[p0] != ',' ||
            data[p0 + 1] != 'f' ||
            data[p0 + 2] != '\0'
        ) {
            continue;
        }

        p0 += 4;
        if (p0 + 4 > length) continue;

        uint32_t bits =
            ((uint32_t)data[p0] << 24) |
            ((uint32_t)data[p0 + 1] << 16) |
            ((uint32_t)data[p0 + 2] << 8) |
            ((uint32_t)data[p0 + 3]);

        float valueFloat = 0.0f;
        memcpy(&valueFloat, &bits, sizeof(valueFloat));

        double value = (double)valueFloat;

        if (
            isfinite(value) &&
            value >= -100.0 &&
            value <= 100.0
        ) {
            *offset = value / 1000.0;
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

            double offset;
            if (extractOffsetFromUDP(buffer, received, &offset)) {
                printf("OFFSET RECU = %+0.3f ms\n", offset * 1000.0);
                fflush(stdout);

                if (fabs(offset - gMTCOffsetSeconds) > 0.0000001) {
                    gMTCOffsetSeconds = offset;
                    printf("OFFSET APPLIQUE = %+0.3f ms\n", gMTCOffsetSeconds * 1000.0);
                    fflush(stdout);
                    /* Un seul locate explicite, puis la cadence QF normale. */
                    sendFullFrame(currentTimeSeconds());
                    gQuarterFrameIndex = 0;
                    gQuarterFrameSnapshotValid = NO;
                }
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

    const double seconds = spp * secondsPerSPP;
    if (fabs(seconds - currentTimeSeconds()) < 0.020) return;
    resetAbsoluteCandidate();
    gPositionSeconds = seconds;

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
    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;
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


static void handlePlay(BOOL start)
{
    const BOOL fresh = absoluteTimeFresh();
    if (fresh) {
        /* La dernière ABS reçue, pas l'ancienne référence de lecture. */
        gPositionSeconds = gLastAbsoluteRawSeconds;
        int h, m, s, f;
        secondsToTC(gPositionSeconds, &h, &m, &s, &f);
        printf("ABS LOCK %02d:%02d:%02d:%02d\n", h, m, s, f);
    } else if (start) {
        /* FA conserve sa sémantique MIDI : départ à zéro sans ABS. */
        gPositionSeconds = 0.0;
    }
    resetAbsoluteCandidate();
    gRunning = YES;
    gPlayStartPositionSeconds = gPositionSeconds;
    gPlayStartedAt = monotonicSeconds();
    gQuarterFrameIndex = 0;
    gQuarterFrameSnapshotValid = NO;
    printf("%s %.3f s [%s]\n", start ? "START" : "CONTINUE",
           gPositionSeconds, fresh ? "ABS" : "FALLBACK");
    sendFullFrame(gPositionSeconds);
}

static void handleStart(void) { handlePlay(YES); }
static void handleContinue(void) { handlePlay(NO); }


static void handleStop(void)
{
    /*
        Un STOP répété alors que le bridge est déjà arrêté
        ne doit pas renvoyer une rafale de MTC Full Frame.
        Les vrais repositionnements à l'arrêt restent gérés
        par setAbsoluteTime().
    */
    if (!gRunning) {
        return;
    }

    gPositionSeconds =
        currentTimeSeconds();

    gRunning = NO;
    resetAbsoluteCandidate();

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
        /* CoreMIDI appelle sur son thread : copier avant le retour, puis
           sérialiser transport, ABS et QF sur la même queue. */
        NSData *bytes = [NSData dataWithBytes:packet->data length:packet->length];
        dispatch_async(dispatch_get_main_queue(), ^{
            parsePacket(bytes.bytes, (UInt16)bytes.length);
        });

        packet =
            MIDIPacketNext(packet);
    }
}

#ifndef CL_MTC_BRIDGE_TEST
int main(int argc, const char * argv[])
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);

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

        if (setupSyncRefUDP() < 0) {
            fprintf(
                stderr,
                "CL Sync Ref indisponible sur UDP localhost:%d\n",
                SYNC_REF_UDP_PORT
            );
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

                sendSyncReference();
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

#endif /* CL_MTC_BRIDGE_TEST */

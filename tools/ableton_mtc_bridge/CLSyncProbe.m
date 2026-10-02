#import "../shared/CLMIDIEndpointNames.h"
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/runtime.h>

#include <arpa/inet.h>
#include <math.h>
#include <mach/mach_time.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include "CLSyncMeterCore.h"
#include "CLSyncMIDIClock.h"

static const char *SOURCE_NAME =
    CL_MIDI_MTC_IAC;

static const int SYNC_REF_UDP_PORT = 20810;


static MIDIClientRef gClient = 0;
static MIDIPortRef gInputPort = 0;
static MIDIEndpointRef gSource = 0;

static CLSyncMeterState gMeter;
static double gLastPrintAt;

static double monotonicSeconds(void)
{
    static mach_timebase_info_data_t tb = {0, 0};

    if (tb.denom == 0) {
        mach_timebase_info(&tb);
    }

    uint64_t ticks =
        mach_continuous_time();

    return
        ((double)ticks *
         (double)tb.numer /
         (double)tb.denom)
        / 1000000000.0;
}


static NSString *endpointName(
    MIDIEndpointRef endpoint
)
{
    CFStringRef name = NULL;

    MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyDisplayName,
        &name
    );

    if (!name) {
        MIDIObjectGetStringProperty(
            endpoint,
            kMIDIPropertyName,
            &name
        );
    }

    if (!name) {
        return @"";
    }

    return CFBridgingRelease(name);
}


static MIDIEndpointRef findSource(
    const char *wanted
)
{
    return CLMIDIFindEndpoint(YES, [NSString stringWithUTF8String:wanted]);
}


static void printMeasurement(void) {
    double now=monotonicSeconds(); CLSyncTick(&gMeter,now);
    if (now-gLastPrintAt<.5) return;
    gLastPrintAt=now;
    CLSyncStats stats=CLSyncStatistics(&gMeter);
    if (getenv("CL_SYNC_TRACE")) fprintf(stderr,"PAIR cycle=%llu rx0=%.9f rx7=%.9f raw=%.9f target=%.9f nominal=%+.6f phase=%+.6f delta=%+.6f\n",(unsigned long long)gMeter.matchedCycle,gMeter.pendingStart,gMeter.pendingEnd,gMeter.pendingRaw,gMeter.pendingTarget,gMeter.nominalDeltaMs,gMeter.phaseCorrectionMs,gMeter.deltaMs);
    if (gMeter.locked)
        printf("%s OFFSET %+.2f DELTA %+.3f AVG %+.3f JIT %.3f ms nominal %+.3f phase %+.3f cycle %llu samples %llu min %+.3f max %+.3f drops %llu lock %.3f s candidates %u residual %+.3f ms\n",
            CLSyncStatus(&gMeter),gMeter.bridgeOffset,gMeter.deltaMs,stats.mean,stats.jitter,
            gMeter.nominalDeltaMs,gMeter.phaseCorrectionMs,
            (unsigned long long)gMeter.matchedCycle,(unsigned long long)gMeter.samples,stats.min,stats.max,
            (unsigned long long)gMeter.drops,now-gMeter.lockSince,gMeter.candidates,gMeter.referenceResidualMs);
    else printf("%s — attente de cycles QF et diagnostics associés\n",CLSyncStatus(&gMeter));
    fflush(stdout);
}
static void midiRead(const MIDIPacketList *packets,void *context,void *connection) {
    const MIDIPacket *packet=&packets->packet[0];
    for (UInt32 i=0;i<packets->numPackets;i++) {
        double arrival=monotonicSeconds();
        uint64_t stamp=packet->timeStamp;
        double now=CLSyncPacketTime(stamp,arrival);
        NSData *data=[NSData dataWithBytes:packet->data length:packet->length];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (getenv("CL_SYNC_TRACE")) { fprintf(stderr,"MIDI %.9f",now); const uint8_t *b=data.bytes; for(NSUInteger j=0;j<data.length;j++) fprintf(stderr," %02x",b[j]); fprintf(stderr," ; host=%llu arrival=%.9f\n",(unsigned long long)stamp,arrival); }
            CLSyncMIDIBytes(&gMeter,data.bytes,data.length,now);
            printMeasurement();
        });
        packet=MIDIPacketNext(packet);
    }
}

static int setupSyncUDP(void)
{
    int fd =
        socket(
            AF_INET,
            SOCK_DGRAM,
            0
        );

    if (fd < 0) {
        perror("socket CLSYNC");
        return -1;
    }

    struct sockaddr_in addr;

    memset(
        &addr,
        0,
        sizeof(addr)
    );

    addr.sin_family =
        AF_INET;

    addr.sin_port =
        htons(SYNC_REF_UDP_PORT);

    addr.sin_addr.s_addr =
        htonl(INADDR_LOOPBACK);

    if (
        bind(
            fd,
            (struct sockaddr *)&addr,
            sizeof(addr)
        ) < 0
    ) {
        perror("bind CLSYNC");
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
            char buffer[512];

            ssize_t n =
                recv(
                    fd,
                    buffer,
                    sizeof(buffer) - 1,
                    0
                );

            if (n <= 0) {
                return;
            }

            buffer[n] = '\0';

            if (n==sizeof(buffer)-1 || memchr(buffer,0,n)) return;
            if (getenv("CL_SYNC_TRACE")) fprintf(stderr,"UDP %.9f %s",monotonicSeconds(),buffer);
            CLSyncDatagram(&gMeter,buffer,monotonicSeconds());
            printMeasurement();
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
        Conserve la dispatch source.
    */
    objc_setAssociatedObject(
        [NSProcessInfo processInfo],
        "CLSyncProbeUDP",
        source,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    return 0;
}


int main(int argc, const char *argv[])
{
    @autoreleasepool {

        printf("\n");
        printf("========================================\n");
        printf(" CL SYNC PROBE — PHASE COMPENSÉE\n");
        printf(" ABS REF ↔ MTC REELLEMENT RECU\n");
        printf(" 25 FPS\n");
        printf("========================================\n\n");

        OSStatus status =
            MIDIClientCreate(
                CFSTR("CL Sync Meter"),
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

        gSource =
            findSource(
                SOURCE_NAME
            );

        if (!gSource) {
            fprintf(
                stderr,
                "Source MIDI introuvable : %s\n",
                SOURCE_NAME
            );
            return 2;
        }

        status =
            MIDIInputPortCreate(
                gClient,
                CFSTR("CL Sync Meter MTC Input"),
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
            return 3;
        }

        status =
            MIDIPortConnectSource(
                gInputPort,
                gSource,
                NULL
            );

        if (status != noErr) {
            fprintf(
                stderr,
                "MIDIPortConnectSource erreur %d\n",
                (int)status
            );
            return 4;
        }

        if (setupSyncUDP() < 0) {
            fprintf(
                stderr,
                "Impossible d'écouter CLSYNC localhost:%d\n",
                SYNC_REF_UDP_PORT
            );
            return 5;
        }

        printf(
            "MTC source : %s\n",
            [endpointName(gSource) UTF8String]
        );

        printf(
            "Référence  : UDP localhost:%d\n",
            SYNC_REF_UDP_PORT
        );

        printf(
            "Affichage  : 2 mesures/seconde\n\n"
        );

        printf(
            "Lance le bridge puis Play dans Ableton.\n"
            "Ctrl+C pour arrêter.\n\n"
        );

        CFRunLoopRun();
    }

    return 0;
}

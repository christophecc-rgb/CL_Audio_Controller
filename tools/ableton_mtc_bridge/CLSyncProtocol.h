#ifndef CL_SYNC_PROTOCOL_H
#define CL_SYNC_PROTOCOL_H
#include "CLSyncTimecode.h"
#include <stdio.h>
#include <string.h>
/* Positional, versioned datagram. Clocks must share the local monotonic epoch. */
typedef struct {
    unsigned long long sequence, instance;
    double raw, bridge, target, offset, age, mono;
    int hasABS, fresh, running, fps;
} CLSyncPacket;
static inline bool CLSyncParse(const char *text, double now, CLSyncPacket *p) {
    int n=0;
    memset(p,0,sizeof(*p));
    if (sscanf(text,"CLSYNC2 %llu %llx %lf %lf %lf %lf %d %d %lf %d %d %lf %n",
        &p->sequence,&p->instance,&p->raw,&p->bridge,&p->target,&p->offset,
        &p->hasABS,&p->fresh,&p->age,&p->running,&p->fps,&p->mono,&n)!=12 || !n || text[n]) return false;
    return p->instance && p->sequence && p->fps==25
        && (p->hasABS==0 || p->hasABS==1) && (p->fresh==0 || p->fresh==1)
        && (p->running==0 || p->running==1) && (!p->fresh || (p->hasABS && p->age<1))
        && isfinite(p->raw) && p->raw>=0 && p->raw<86400
        && isfinite(p->bridge) && p->bridge>=0 && p->bridge<86400
        && isfinite(p->target) && p->target>=0 && p->target<86400
        && isfinite(p->offset) && fabs(p->offset)<=86400000
        && isfinite(p->age) && p->age>=0 && isfinite(p->mono)
        && p->mono>0 && p->mono<=now+.010 && now-p->mono<=.5
        && fabs(wrappedDifference(p->target,wrapSeconds(p->bridge+p->offset/1000)))<.00001;
}
/* Optional cycle instrumentation; CLSYNC2 heartbeat remains unchanged. */
typedef struct {
    unsigned long long instance, epoch, cycle;
    double raw, snapshot, mono, start, end, offset;
} CLSyncCyclePacket;
static inline bool CLSyncParseCycle(const char *text,double now,CLSyncCyclePacket *p) {
    int n=0; memset(p,0,sizeof(*p));
    if (sscanf(text,"CLSYNCQ2 %llx %llu %llu %lf %lf %lf %lf %lf %lf %n",
        &p->instance,&p->epoch,&p->cycle,&p->raw,&p->snapshot,&p->mono,&p->start,&p->end,&p->offset,&n)!=9 || !n || text[n]) return false;
    double fraction=wrappedDifference(p->snapshot,p->raw);
    return p->instance && p->epoch && p->cycle && isfinite(p->raw) && p->raw>=0 && p->raw<86400
        && isfinite(p->snapshot) && p->snapshot>=0 && p->snapshot<86400
        && fraction>=-.000001 && fraction<.040001
        && isfinite(p->mono) && p->mono>0 && isfinite(p->start) && isfinite(p->end)
        && p->start>=p->mono && p->start-p->mono<.010
        && p->end-p->start>=.040 && p->end-p->start<=.120
        && p->end<=now+.010 && now-p->end<=.250
        && isfinite(p->offset) && fabs(p->offset)<=86400000;
}
#endif

#ifndef CL_SYNC_METER_CORE_H
#define CL_SYNC_METER_CORE_H
#include "CLSyncProtocol.h"
#include <stdio.h>
#include <string.h>

#define CL_SYNC_HISTORY 125
#define CL_SYNC_TIMEOUT 0.250
/* Pure measurement state, no MIDI output and no bridge control. All times use
   mach_continuous_time seconds, as in CLSyncProbe and the diagnostic sender. */
typedef struct {
    bool hasRef, running, hasMTC, locked, pendingQF;
    uint64_t sequence, samples, drops, instance;
    bool hasABS, absFresh;
    double absRaw, bridgeSeconds, absAge, playSince, observedAt;
    double refSeconds, refMono, refArrival, bridgeOffset;
    double lastQF, lastCycle, cycleMs, mtcSeconds, measuredRef, deltaMs, lockSince;
    uint8_t qf[8], nextQF;
    uint8_t sysex[10], sysexLength;
    bool inSysex, cyclePending;
    double lastQFSeen, cycleStart, pendingStart, pendingEnd, pendingRaw, pendingTarget, resetAt, lastMeasurement;
    CLSyncCyclePacket diagnostic[8];
    unsigned diagnosticCursor;
    uint64_t matchedCycle, epoch;
    double boundaryMono, lastMatchedEnd;
    unsigned candidates;
    double rxStamps[8], matchedSend0, matchedSend7, referenceResidualMs;
    double phaseCorrectionMs, nominalDeltaMs;
    double history[CL_SYNC_HISTORY];
    unsigned count, cursor;
} CLSyncMeterState;

typedef struct { double mean, min, max, jitter; } CLSyncStats;

static inline void CLSyncResetStats(CLSyncMeterState *s) {
    s->cyclePending=false; s->resetAt=s->observedAt;
    memset(s->diagnostic,0,sizeof(s->diagnostic));
    s->samples=0; s->count=0; s->cursor=0; s->locked=false; s->lockSince=0;
}
static inline void CLSyncBreak(CLSyncMeterState *s, bool drop) {
    if (drop && s->locked) s->drops++;
    CLSyncResetStats(s);
    s->hasMTC=false; s->nextQF=0; s->pendingQF=false;
    s->lastQF=0; s->lastCycle=0; s->cycleMs=0;
}
static inline void CLSyncTick(CLSyncMeterState *s, double now) {
    s->observedAt=fmax(s->observedAt,now);
    if (s->hasRef && now-s->refArrival > 0.500) {
        CLSyncBreak(s,true); s->hasRef=false;
    }
    if (s->absFresh && s->absAge+now-s->refMono>=1.0) {
        s->absFresh=false; CLSyncBreak(s,false);
    }
    if (s->lastQF > 0 && now-s->lastQF > CL_SYNC_TIMEOUT) CLSyncBreak(s,true);
    if (s->locked && now-s->lastMeasurement>.250) CLSyncResetStats(s);
}
static inline bool CLSyncReference(CLSyncMeterState *s, const char *text, double now) {
    CLSyncPacket p;
    if (!CLSyncParse(text,now,&p)) return false;
    // Keep the last timestamp even offline: queued packets cannot revive an old instance.
    if (s->instance && (p.mono<=s->refMono || (p.instance==s->instance && p.sequence<=s->sequence))) return false;
    CLSyncTick(s,now);
    bool fresh=p.fresh && p.age+fmax(0,now-p.mono)<1.0;
    if (p.instance!=s->instance) {
        CLSyncBreak(s,false); s->matchedCycle=0; s->epoch=0; s->boundaryMono=0; s->lastMatchedEnd=0; s->drops=0; s->playSince=now;
    } else if (s->hasRef) {
        double projected=wrapSeconds(s->refSeconds+(s->running?p.mono-s->refMono:0));
        bool jump=fabs(wrappedDifference(p.target,projected))>.120 || fabs(p.offset-s->bridgeOffset)>.001;
        if (s->running!=(bool)p.running || jump) { CLSyncBreak(s,false); s->playSince=now; }
        if (s->absFresh!=fresh) CLSyncBreak(s,false);
    }
    s->hasRef=true; s->running=p.running; s->sequence=p.sequence; s->instance=p.instance;
    s->refSeconds=p.target; s->refMono=p.mono; s->refArrival=now; s->bridgeOffset=p.offset;
    s->hasABS=p.hasABS; s->absFresh=fresh; s->absRaw=p.raw; s->absAge=p.age; s->bridgeSeconds=p.bridge;
    return true;
}

static inline void CLSyncMatchCycle(CLSyncMeterState *s) {
    if (!s->cyclePending || !s->hasRef || !s->running) return;
    CLSyncCyclePacket *chosen=NULL;
    s->candidates=0;
    for (unsigned i=0;i<8;i++) {
        CLSyncCyclePacket *p=&s->diagnostic[i];
        if (p->instance!=s->instance || p->epoch!=s->epoch || p->cycle<=s->matchedCycle
            || p->mono<s->resetAt || p->start<=s->lastMatchedEnd
            || fabs(p->offset-s->bridgeOffset)>.001
            || fabs(wrappedDifference(p->raw,s->pendingRaw))>.00001
            || s->pendingStart-p->start<-.0005 || s->pendingStart-p->start>.030
            || s->pendingEnd-p->end<-.0005 || s->pendingEnd-p->end>.030) continue;
        s->candidates++; chosen=p;
    }
    if (s->candidates!=1) {
        if (s->candidates>1) CLSyncBreak(s,true);
        return;
    }
    CLSyncCyclePacket *p=chosen;
    // A discontinuous/stale heartbeat is not allowed to bias an otherwise
    // correctly correlated cycle. Report the residual for diagnosis.
    double cycleTarget=wrapSeconds(p->snapshot+s->pendingEnd-p->mono);
    s->referenceResidualMs=wrappedDifference(s->pendingTarget,cycleTarget)*1000;
    if (fabs(s->referenceResidualMs)>5.0) { CLSyncBreak(s,true); return; }
    {
        // Nominal forward decoder (+2 frames) is retained. Remove its phase
        // error using the measured sender interval and subframe truncation.
        double phase=wrappedDifference(p->snapshot,p->raw)+(p->end-p->mono)-.080;
        double nominal=wrapSeconds(s->pendingRaw+.080);
        s->nominalDeltaMs=wrappedDifference(nominal,s->pendingTarget)*1000;
        s->phaseCorrectionMs=phase*1000;
        s->mtcSeconds=wrapSeconds(nominal+phase);
        s->measuredRef=s->pendingTarget;
        double delta=wrappedDifference(s->mtcSeconds,s->measuredRef)*1000;
        s->cyclePending=false; s->matchedCycle=p->cycle;
        s->lastMatchedEnd=p->end; s->matchedSend0=p->start; s->matchedSend7=p->end;
        if (!isfinite(delta) || fabs(delta)>1000) { CLSyncBreak(s,true); return; }
        s->deltaMs=delta; s->history[s->cursor]=delta;
        s->cursor=(s->cursor+1)%CL_SYNC_HISTORY;
        if (s->count<CL_SYNC_HISTORY) s->count++;
        s->samples++; s->lastMeasurement=s->pendingEnd;
        if (!s->locked) { s->locked=true; s->lockSince=s->pendingEnd; }
        return;
    }
}
static inline bool CLSyncBoundary(CLSyncMeterState *s,const char *text,double now) {
    unsigned long long instance=0,epoch=0; double mono=0,offset=0;int running=0,n=0;
    if (sscanf(text,"CLSYNCB1 %llx %llu %lf %lf %d %n",&instance,&epoch,&mono,&offset,&running,&n)!=5
        || !n || text[n] || instance!=s->instance || epoch<=s->epoch
        || !isfinite(mono) || mono<=s->boundaryMono || mono>now+.010 || now-mono>.5
        || !isfinite(offset) || fabs(offset)>86400000 || (running!=0 && running!=1)) return false;
    s->observedAt=fmax(s->observedAt,mono); CLSyncBreak(s,false);
    s->epoch=epoch; s->boundaryMono=mono;
    return true;
}
static inline bool CLSyncDiagnostic(CLSyncMeterState *s,const char *text,double now) {
    CLSyncCyclePacket p;
    if (!CLSyncParseCycle(text,now,&p) || p.instance!=s->instance || p.mono<s->resetAt
        || p.cycle<=s->matchedCycle || p.epoch<s->epoch || fabs(p.offset-s->bridgeOffset)>.001) return false;
    if (p.epoch>s->epoch) {
        // Also establishes a boundary if its UDP event was lost. Discard any
        // pending MIDI cycle; reacquire strictly after this diagnostic.
        CLSyncBreak(s,false); s->epoch=p.epoch; s->boundaryMono=p.mono;
        s->resetAt=fmax(s->resetAt,p.end); return false;
    }
    for(unsigned i=0;i<8;i++) if(s->diagnostic[i].cycle==p.cycle) return false;
    s->diagnostic[s->diagnosticCursor++%8]=p;
    CLSyncMatchCycle(s);
    return true;
}
static inline bool CLSyncDatagram(CLSyncMeterState *s,const char *text,double now) {
    if (!strncmp(text,"CLSYNCQ2 ",9)) return CLSyncDiagnostic(s,text,now);
    if (!strncmp(text,"CLSYNCB1 ",9)) return CLSyncBoundary(s,text,now);
    return CLSyncReference(s,text,now);
}
static inline void CLSyncQuarterFrame(CLSyncMeterState *s, uint8_t value, double now) {
    CLSyncTick(s,now);
    unsigned index=(value>>4)&7;
    s->lastQF=now; s->lastQFSeen=now;
    if (index!=s->nextQF) {
        // No mixed cycle after loss/reordering. Restart only at nibble zero.
        CLSyncBreak(s,true);
        s->lastQF=now;
        if (index!=0) return;
    }
    if (index==0) {
        if (s->cyclePending) { CLSyncBreak(s,true); s->lastQF=now; }
        s->cycleStart=now;
    } else if (now<=s->rxStamps[index-1] || now-s->rxStamps[index-1]>.030) {
        CLSyncBreak(s,true); return;
    }
    s->rxStamps[index]=now;
    s->qf[index]=value&15;
    s->nextQF=(index+1)%8;
    if (index!=7) return;
    double corrected=0;
    if (!CLSyncDecodeQF(s->qf,&corrected)) { CLSyncBreak(s,true); return; }
    double previousCycle=s->lastCycle;
    s->cycleMs=previousCycle>0?(now-previousCycle)*1000:0;
    s->lastCycle=now; s->hasMTC=true;
    if (!s->locked) s->mtcSeconds=corrected;
    if (!s->hasRef || !s->running) return;
    // The first complete cycle after a reset establishes phase, not lock.
    if (previousCycle<=0 || s->cycleMs<40 || s->cycleMs>120) {
        if (s->locked) { CLSyncBreak(s,true); s->lastQF=now; }
        return;
    }
    s->cyclePending=true; s->pendingStart=s->cycleStart; s->pendingEnd=now;
    s->pendingRaw=wrapSeconds(corrected-.080);
    s->pendingTarget=wrapSeconds(s->refSeconds+now-s->refMono);
    CLSyncMatchCycle(s);
}

static inline void CLSyncMIDIBytes(CLSyncMeterState *s,const uint8_t *data,size_t length,double now) {
    for (size_t i=0;i<length;i++) {
        uint8_t byte=data[i];
        if (byte>=0xF8) continue; // Realtime bytes may interrupt an F1 message.
        if (byte==0xF0) { s->inSysex=true; s->sysexLength=0; s->pendingQF=false; }
        if (s->inSysex) {
            if (s->sysexLength<10) s->sysex[s->sysexLength++]=byte;
            else { s->inSysex=false; s->sysexLength=0; }
            if (byte==0xF7) {
                s->inSysex=false;
                if (s->sysexLength==10 && s->sysex[1]==0x7F && s->sysex[3]==1 && s->sysex[4]==1) {
                    s->observedAt=now; CLSyncBreak(s,false);
                }
            }
            continue;
        }
        if (byte==0xF1) { s->pendingQF=true; continue; }
        if (byte&0x80) { s->pendingQF=false; continue; }
        if (s->pendingQF) { s->pendingQF=false; CLSyncQuarterFrame(s,byte,now); }
    }
}
static inline CLSyncStats CLSyncStatistics(const CLSyncMeterState *s) {
    CLSyncStats v={0};
    if (!s->count) return v;
    v.min=v.max=s->history[0];
    for(unsigned i=0;i<s->count;i++) {
        double x=s->history[i]; v.mean+=x; v.min=fmin(v.min,x); v.max=fmax(v.max,x);
    }
    v.mean/=s->count;
    for(unsigned i=0;i<s->count;i++) v.jitter+=(s->history[i]-v.mean)*(s->history[i]-v.mean);
    v.jitter=sqrt(v.jitter/s->count);
    return v;
}
static inline bool CLSyncCanRecommend(const CLSyncMeterState *s) {
    return s->hasRef && s->running && s->absFresh && s->locked && !s->cyclePending && s->count>=25
        && s->observedAt-s->resetAt>=2.0 && CLSyncStatistics(s).jitter<=2.0;
}
static inline const char *CLSyncStatus(const CLSyncMeterState *s) {
    if (!s->hasRef) return "OFFLINE";
    if (!s->running) return "STOPPED";
    if (!s->hasMTC) {
        if (s->observedAt-fmax(s->playSince,s->lastQFSeen)>.250) return "NO MTC";
        return s->absFresh?"ACQUIRING":"NO REF";
    }
    if (!s->absFresh) return "FREE-RUN";
    return s->locked && !s->cyclePending?"LOCKED":"ACQUIRING";
}
#endif

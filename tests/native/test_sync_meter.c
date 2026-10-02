#include "../../tools/ableton_mtc_bridge/CLSyncMeterCore.h"
#include <assert.h>
#include <stdio.h>
static void ref(CLSyncMeterState *s,unsigned seq,double mono,double pos,int playing) {
    char text[256];snprintf(text,sizeof(text),"CLSYNC2 %u %x %.9f %.9f %.9f 0 1 1 0 %d 25 %.9f\n",seq,(mono>=101?2:1),pos,pos,pos,playing,mono);
    assert(CLSyncReference(s,text,mono));
    if (!s->epoch) { snprintf(text,sizeof text,"CLSYNCB1 %llx 1 %.9f 0 %d",(unsigned long long)s->instance,mono,playing); assert(CLSyncBoundary(s,text,mono)); }
}
static void cycle(CLSyncMeterState *s,double raw,double end) {
    int h,m,sec,f;secondsToTC(raw,&h,&m,&sec,&f);
    uint8_t q[]={f&15,(f>>4)&1,sec&15,(sec>>4)&3,m&15,(m>>4)&3,h&15,((h>>4)&1)|2};
    for(int i=0;i<8;i++) {
        uint8_t bytes[]={0xF1,(uint8_t)((i<<4)|q[i])};
        CLSyncMIDIBytes(s,bytes,2,end-.07+.01*i);
    }
    char diagnostic[256];
    snprintf(diagnostic,sizeof(diagnostic),"CLSYNCQ2 %llx 1 %llu %.9f %.9f %.9f %.9f %.9f %.6f",
        (unsigned long long)s->instance,(unsigned long long)(end*10000),
        tcToSeconds(h,m,sec,f),tcToSeconds(h,m,sec,f),end-.080,end-.071,end,s->bridgeOffset);
    CLSyncDiagnostic(s,diagnostic,end);

}
int main(void) {
    CLSyncMeterState s={0};
    assert(strcmp(CLSyncStatus(&s),"OFFLINE")==0);
    assert(!CLSyncReference(&s,"CLSYNC1 1 nan 100 1 25 0",100));
    assert(!CLSyncReference(&s,"CLSYNC1 1 0 inf 1 25 0",100));
    assert(!CLSyncReference(&s,"CLSYNC1 1 0 100 1 24 0",100));
    assert(!CLSyncReference(&s,"CLSYNC1 1 0 1 1 25 0",100));
    assert(!CLSyncReference(&s,"CLSYNC1 1 0 100 1 25 0 garbage",100));
    ref(&s,1,100,18000-.0024,1);
    assert(strcmp(CLSyncStatus(&s),"ACQUIRING")==0);
    cycle(&s,18000,100.08);assert(!s.locked);
    cycle(&s,18000.08,100.16);assert(s.locked && s.samples==1);
    assert(fabs(s.deltaMs-2.4)<.0001);assert(fabs(s.cycleMs-80)<.0001);
    CLSyncStats stats=CLSyncStatistics(&s);assert(fabs(stats.mean-2.4)<.0001 && stats.jitter==0);
    ref(&s,2,100.17,18000.1676,0);assert(!s.locked && s.samples==0 && s.drops==0);
    assert(strcmp(CLSyncStatus(&s),"STOPPED")==0);
    ref(&s,3,100.20,18000.20-.0024,1);
    cycle(&s,18000.20,100.28);cycle(&s,18000.28,100.36);
    assert(s.locked && s.samples==1);
    CLSyncTick(&s,100.62);assert(!s.locked && s.samples==0 && s.drops==1);
    CLSyncTick(&s,101);assert(s.drops==1);
    ref(&s,1,101,18010,1);cycle(&s,18010,101.08);cycle(&s,18010.08,101.16);
    assert(s.locked && fabs(s.deltaMs)<.0001);
    ref(&s,2,101.17,18050,1);assert(!s.locked && s.count==0); // Locate.
    cycle(&s,18050.01,101.25); // Incomplete/invalid order breaks lock.
    CLSyncQuarterFrame(&s,0x31,101.26);assert(!s.locked);
    // Midnight wrap and shared probe nominal +2 correction.
    uint8_t last[]={8,1,11,3,11,3,7,3};double corrected=0;
    assert(CLSyncDecodeQF(last,&corrected));assert(fabs(corrected-.04)<.0001);
    assert(fabs(wrappedDifference(.001,86399.999)-.002)<.0001);
    CLSyncMeterState m={0};
    cycle(&m,100,100.08);assert(m.hasMTC && !m.hasRef);
    assert(strcmp(CLSyncStatus(&m),"OFFLINE")==0);
    CLSyncBreak(&m,false);assert(m.count==0);
    // Split F1/data and interleaved realtime bytes survive packet boundaries.
    uint8_t a[]={0xF1},b[]={0xF8,0x00};
    CLSyncMIDIBytes(&m,a,1,200);CLSyncMIDIBytes(&m,b,2,200.01);assert(m.nextQF==1);
    // V2 freshness, free-run, reacquisition and configured offset are independent.
    CLSyncMeterState v={0};
    ref(&v,1,300,18000,1);
    cycle(&v,18000,300.08); cycle(&v,18000.08,300.16);
    assert(!strcmp(CLSyncStatus(&v),"LOCKED"));
    assert(CLSyncReference(&v,"CLSYNC2 2 2 17999 18000.17 18000.17 0 1 0 1.2 1 25 300.17",300.17));
    assert(!v.count && !v.locked);
    cycle(&v,18000.16,300.24);cycle(&v,18000.24,300.32);
    assert(v.locked && !strcmp(CLSyncStatus(&v),"FREE-RUN"));
    assert(CLSyncReference(&v,"CLSYNC2 3 2 18000.33 18000.33 18000.33 0 1 1 0 1 25 300.33",300.33));
    assert(!v.count && !strcmp(CLSyncStatus(&v),"ACQUIRING"));
    cycle(&v,18000.32,300.40);cycle(&v,18000.40,300.48); assert(!strcmp(CLSyncStatus(&v),"LOCKED"));
    assert(CLSyncReference(&v,"CLSYNC2 4 2 18000.50 18000.50 18000.52 20 1 1 0 1 25 300.50",300.50));
    cycle(&v,18000.52,300.58);cycle(&v,18000.60,300.66);
    assert(v.bridgeOffset==20 && fabs(v.deltaMs)<.001);
    assert(CLSyncReference(&v,"CLSYNC2 5 2 18001.0 18001.0 18001.02 20 1 1 0 1 25 301.0",301.0));
    assert(!strcmp(CLSyncStatus(&v),"NO MTC"));
    CLSyncTick(&v,301.51);assert(!strcmp(CLSyncStatus(&v),"OFFLINE"));
    assert(CLSyncReference(&v,"CLSYNC2 1 3 18001.32 18001.32 18001.32 0 1 1 0 1 25 301.52",301.52));
    assert(v.instance==3 && !v.count && !v.samples && !v.drops);
    assert(!CLSyncReference(&v,"CLSYNC2 6 2 18001.3 18001.3 18001.3 0 1 1 0 1 25 301.50",301.53));
    assert(!CLSyncReference(&v,"CLSYNC2 1 3 18001.32 18001.32 18001.32 0 1 1 0 1 25 301.52",301.53));
    assert(!CLSyncReference(&v,"CLSYNC2 2 3 nan 1 1 0 1 1 0 1 25 301.54",301.54));
    assert(!CLSyncReference(&v,"CLSYNC2 2 3 1 1 inf 0 1 1 0 1 25 301.54",301.54));
    assert(!CLSyncReference(&v,"CLSYNC2 2 3 1 1 1 0 0 1 0 1 25 301.54",301.54));
    puts("PASS: lock, 25 fps +2 frames, offset, wrap, Stop/Play, drop reset, locate, invalid REF, MIDI framing");
    return 0;
}

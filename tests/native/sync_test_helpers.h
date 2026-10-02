#ifndef SYNC_TEST_HELPERS_H
#define SYNC_TEST_HELPERS_H
#include "../../tools/ableton_mtc_bridge/CLSyncMeterCore.h"
#include <assert.h>
#include <stdio.h>
static void heartbeat(CLSyncMeterState *s,unsigned seq,double t,double target,double off) {
    char b[512];
    snprintf(b,sizeof b,"CLSYNC2 %u abc %.9f %.9f %.9f %.6f 1 1 0 1 25 %.9f",
        seq,wrapSeconds(target-off),wrapSeconds(target-off),wrapSeconds(target),off*1000,t);
    assert(CLSyncDatagram(s,b,t));
    if(!s->epoch) { snprintf(b,sizeof b,"CLSYNCB1 abc 1 %.9f %.6f 1",t,off*1000); assert(CLSyncDatagram(s,b,t)); }
}
static void midi(CLSyncMeterState *s,double raw,double start,int first) {
    int h,m,sec,f;secondsToTC(raw,&h,&m,&sec,&f);
    uint8_t q[]={f&15,(f>>4)&1,sec&15,(sec>>4)&3,m&15,(m>>4)&3,h&15,((h>>4)&1)|2};
    for(int i=first;i<8;i++) {
        uint8_t b[]={0xF1,(uint8_t)(i*16+q[i])};
        CLSyncMIDIBytes(s,b,2,start+.01*i+.003); // 3 ms actual receive delay => negative position delta.
    }
}
#endif

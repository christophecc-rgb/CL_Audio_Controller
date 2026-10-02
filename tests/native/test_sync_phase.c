#include "sync_test_helpers.h"
int main(void) {
    double offsets[]={0,.100,-.100,.020,0};
    for(int phase=0;phase<8;phase++) {
        CLSyncMeterState s={0};unsigned seq=0;uint64_t id=0;
        for(int segment=0;segment<5;segment++) {
            double off=offsets[segment], origin=100+segment*2;
            heartbeat(&s,++seq,origin,18000.019+segment*2+off,off);
            assert(!s.count && !s.locked);
            double oldMean=0;unsigned oldCount=0;
            for(int c=0;c<12;c++) {
                double start=origin+.08*c;
                // Vary initial sender phase too; it is independent of MTC frame boundaries.
                double target=18000.019+segment*2+.08*c+off+phase*.001;
                if(c) heartbeat(&s,++seq,start-.001,target-.001,off);
                double raw=floor(target*25+.000001)/25;
                char d[256];snprintf(d,sizeof d,"CLSYNCQ2 abc 1 %llu %.9f %.9f %.9f %.9f %.9f %.6f",
                    (unsigned long long)++id,raw,target,start,start,start+.07,off*1000);
                // Exercise either UDP/MIDI callback delivery order.
                if(c%2) CLSyncDatagram(&s,d,start+.071);
                midi(&s,raw,start,c?0:phase);
                if(!(c%2)) CLSyncDatagram(&s,d,start+.075);
                if(c>=3) {
                    assert(s.locked);
                    assert(fabs(s.deltaMs+3)<.001);
                    oldMean+=s.nominalDeltaMs;oldCount++;
                }
            }
            CLSyncStats stats=CLSyncStatistics(&s);
            assert(fabs(stats.mean+3)<.001 && stats.jitter<.001);
            if(!phase) printf("offset %+.0f ms: before %+.3f, after %+.3f, jitter %.6f ms\n",off*1000,oldMean/oldCount,stats.mean,stats.jitter);
            // Full Frame split across packets, realtime interleaving: invalidate immediately.
            uint8_t a[]={0xF0,0x7F,0x7F,1,0xF8},b[]={1,0x20,0,0,0,0xF7};
            CLSyncMIDIBytes(&s,a,sizeof a,origin+1);
            CLSyncMIDIBytes(&s,b,sizeof b,origin+1.001);
            assert(!s.locked && !s.count && !s.nextQF);
        }
    }
    // Missing instrumentation: never claim reliable lock or offer correction.
    CLSyncMeterState m={0};heartbeat(&m,1,100,18000,0);
    midi(&m,18000,100,0);midi(&m,18000.08,100.08,0);
    assert(m.hasMTC && !m.locked && !m.count);
    assert(!CLSyncDiagnostic(&m,"CLSYNCQ2 abc 1 1 nan 0 100 100 100.07 0",100.08));
    assert(!CLSyncDiagnostic(&m,"CLSYNCQ2 def 1 1 18000 18000 100 100 100.07 0",100.08));
    puts("PASS: 5 offsets x 8 initial QF phases, 3ms delay, callback order, Full Frame, missing diagnostics");
}

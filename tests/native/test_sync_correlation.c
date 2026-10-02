#include "sync_test_helpers.h"

static void diagnostic(char *b,size_t n,uint64_t epoch,uint64_t id,double start,double target,double off) {
    double raw=floor(target*25+.000001)/25;
    snprintf(b,n,"CLSYNCQ2 abc %llu %llu %.9f %.9f %.9f %.9f %.9f %.6f",
        (unsigned long long)epoch,(unsigned long long)id,raw,target,start,start,start+.07,off*1000);
}
static void boundary(CLSyncMeterState *s,double t,uint64_t epoch) {
    char b[256]; snprintf(b,sizeof b,"CLSYNCB1 abc %llu %.9f 0 1",(unsigned long long)epoch,t);
    assert(CLSyncDatagram(s,b,t));
}
static void feed(CLSyncMeterState *s,double start,double target,uint64_t id) {
    heartbeat(s,(unsigned)s->sequence+1,start-.001,target-.001,0);
    char b[256];diagnostic(b,sizeof b,s->epoch,id,start,target,0);
    midi(s,floor(target*25+.000001)/25,start,0);
    CLSyncDatagram(s,b,start+.075);
}
int main(void) {
    CLSyncMeterState s={0};heartbeat(&s,1,100,18000,0);
    uint64_t id=0;
    // Stop/Play and locate boundaries: never reuse previous metadata/statistics.
    for(int run=0;run<10;run++) {
        double start=101+run*5, target=18000+run*111.137;
        char stop[256];
        snprintf(stop,sizeof stop,"CLSYNC2 %llu abc %.9f %.9f %.9f 0 1 1 0 0 25 %.9f",
            (unsigned long long)s.sequence+1,target,target,target,start-.1);
        assert(CLSyncDatagram(&s,stop,start-.1)); assert(!s.count && !s.locked);
        heartbeat(&s,(unsigned)s.sequence+1,start-.01,target-.01,0);
        boundary(&s,start-.009,(uint64_t)run+2);
        assert(!s.count && !CLSyncCanRecommend(&s));
        for(int c=0;c<30;c++) {
            feed(&s,start+c*.08,target+c*.08,++id);
            if(c<25) assert(!CLSyncCanRecommend(&s));
        }
        assert(s.locked && CLSyncCanRecommend(&s));
        assert(fabs(CLSyncStatistics(&s).mean+3)<.001);
    }
    // Cycle N metadata lost; N+1 must not consume it when it arrives late.
    double start=160,target=20000;
    boundary(&s,159.99,20);
    feed(&s,start,target,++id);feed(&s,start+.08,target+.08,++id);
    assert(s.locked);
    heartbeat(&s,(unsigned)s.sequence+1,start+.159,target+.159,0);
    midi(&s,floor((target+.16)*25+.000001)/25,start+.16,0);
    char lost[256];diagnostic(lost,sizeof lost,20,++id,start+.16,target+.16,0);
    feed(&s,start+.24,target+.24,++id);assert(!s.locked);
    assert(!CLSyncDatagram(&s,lost,start+.315));
    feed(&s,start+.32,target+.32,++id);assert(s.locked);
    unsigned samples=s.samples;
    char duplicate[256];diagnostic(duplicate,sizeof duplicate,20,id,start+.32,target+.32,0);
    assert(!CLSyncDatagram(&s,duplicate,start+.395));assert(s.samples==samples);
    // Two plausible diagnostics are ambiguous, even if raw timecode matches.
    boundary(&s,170,21);feed(&s,170.01,21000,++id);
    heartbeat(&s,(unsigned)s.sequence+1,170.089,21000.079,0);
    char a[256],b[256];
    diagnostic(a,sizeof a,21,++id,170.09,21000.08,0);
    diagnostic(b,sizeof b,21,++id,170.0901,21000.0801,0);
    assert(CLSyncDatagram(&s,a,170.161));assert(CLSyncDatagram(&s,b,170.161));
    midi(&s,21000.08,170.09,0);assert(!s.locked && !s.count);
    // Old epoch, malformed ordering and timestamp batching cannot acquire.
    assert(!CLSyncDatagram(&s,lost,170.2));
    CLSyncQuarterFrame(&s,0,170.21);CLSyncQuarterFrame(&s,0x10,170.21);
    assert(!s.locked && !s.nextQF);
    puts("PASS: 10 Stop/Play + locates, >=25 reliable samples, lost/late/duplicate/ambiguous diagnostics, epoch and timestamp rejection");
}

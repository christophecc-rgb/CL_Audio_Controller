/* Real bridge handlers, deterministic clock, captured MIDI; no ports/processes. */
#define CL_MTC_BRIDGE_TEST 1
#import "../../tools/ableton_mtc_bridge/CLAbletonMTCBridge.m"
#include <assert.h>
double clTestNow = 100;
static unsigned fullCount, qfCount;
static UInt8 lastQF;
void clTestSend(const UInt8 *bytes, UInt16 length) {
    if (bytes[0] == 0xF0) { assert(length == 10); ++fullCount; }
    else { assert(length == 2 && bytes[0] == 0xF1); lastQF = bytes[1]; ++qfCount; }
}
static void near(double a, double b) { assert(fabs(a-b) < 1e-6); }
static void absAt(double seconds) {
    int h,m,s,f;
    secondsToTC(seconds + 1e-7,&h,&m,&s,&f);
    setAbsoluteTime(h,m,s,f);
}
static void reset(void) {
    gRunning=NO; gHasAbsoluteTime=NO; gPositionSeconds=0;
    gPlayStartPositionSeconds=0; gPlayStartedAt=0; gTempo=120;
    gQuarterFrameIndex=0; gQuarterFrameSnapshotValid=NO;
    fullCount=qfCount=0; clTestNow=100; resetAbsoluteCandidate();
}
int main(void) {
    @autoreleasepool {
        reset(); absAt(7209.16); unsigned n=fullCount;
        handleStart(); near(currentTimeSeconds(),7209.16); assert(fullCount==n+1);
        setSongPosition(16); near(currentTimeSeconds(),7209.16); assert(fullCount==n+1);
        // Fresh ABS must win even when the old locked position differs.
        clTestNow+=.04; absAt(7209.24); handleContinue();
        near(currentTimeSeconds(),7209.24);
        n=fullCount;
        for (int i=0;i<800;i++) {
            clTestNow+=.01;
            if (i%4==0) absAt(currentTimeSeconds()+(i%8 ? .08 : -.08));
            sendQuarterFrame(); assert((lastQF>>4)==i%8);
        }
        assert(qfCount==800 && fullCount==n); near(currentTimeSeconds(),7217.24);
        // An isolated large outlier and inconsistent medium errors never locate.
        clTestNow+=.04; absAt(currentTimeSeconds()+1.44); assert(fullCount==n);
        clTestNow+=.04; absAt(currentTimeSeconds()); assert(fullCount==n);
        for (int i=0;i<10;i++) {
            clTestNow+=.04; absAt(currentTimeSeconds()+(i%2 ? .32 : -.32));
        }
        assert(fullCount==n);
        clTestNow+=.04; absAt(currentTimeSeconds());
        // Persistent medium drift: no correction on the first five observations.
        for (int i=0;i<6;i++) {
            clTestNow+=.04; absAt(currentTimeSeconds()+.32);
            assert(fullCount==n+(i==5));
        }
        n=fullCount;
        // Observed backwards locates: next coherent measurement confirms.
        for (int jump=0;jump<2;jump++) {
            double delta=jump ? -4.72 : -9.16;
            clTestNow+=.04; absAt(currentTimeSeconds()+delta); assert(fullCount==n);
            double target=currentTimeSeconds()+delta+.04;
            clTestNow+=.04; absAt(target); assert(fullCount==++n);
            near(currentTimeSeconds(),floor((target+1e-7)*25)/25);
        }
        // A UDP burst without elapsed time cannot confirm a correction.
        for (int i=0;i<20;i++) absAt(currentTimeSeconds()+2);
        assert(fullCount==n);
        clTestNow+=.24; absAt(currentTimeSeconds()+2); assert(fullCount==n);
        clTestNow+=.04; absAt(currentTimeSeconds());
        handleStop(); assert(fullCount==++n); double stopped=currentTimeSeconds();
        unsigned q=qfCount; clTestNow+=2; sendQuarterFrame(); handleStop();
        assert(qfCount==q && fullCount==n); near(currentTimeSeconds(),stopped);
        absAt(8000); handleContinue(); near(currentTimeSeconds(),8000);
        assert(gAbsoluteCandidateCount==0); sendQuarterFrame(); assert(qfCount==q+1);
        reset(); setSongPosition(80); near(currentTimeSeconds(),10);
        n=fullCount; setSongPosition(80); assert(fullCount==n);
        handleContinue(); near(currentTimeSeconds(),10);
        clTestNow+=1; near(currentTimeSeconds(),11);
        handleStop(); handleStart(); near(currentTimeSeconds(),0);
        reset(); absAt(100); clTestNow+=1.01; setSongPosition(80);
        handleContinue(); near(currentTimeSeconds(),10); // stale ABS does not win
        reset(); absAt(86399.96); handleStart(); n=fullCount;
        for (int i=0;i<10;i++) { clTestNow+=.04; absAt(fmod(currentTimeSeconds(),86400)); }
        assert(fullCount==n); // midnight is not a locate
        reset(); handleContinue(); n=fullCount;
        // First ABS during fallback playback also needs confirmation.
        absAt(1.44); assert(fullCount==n);
        clTestNow+=.04; absAt(1.48); assert(fullCount==n+1);
        near(currentTimeSeconds(),1.48);
        sendQuarterFrame(); assert((lastQF>>4)==0);
        for (int i=1;i<8;i++) { clTestNow+=.01; sendQuarterFrame(); }
        assert(lastQF==0x72); // 25 fps in the hour/rate nibble
        // The actual MIDI parser drives Stop and Continue, too.
        const UInt8 stop[]={0xFC}, resume[]={0xFB};
        parsePacket(stop,1); assert(!gRunning);
        parsePacket(resume,1); assert(gRunning);
        puts("MTC bridge behavior: OK");
    }
    return 0;
}

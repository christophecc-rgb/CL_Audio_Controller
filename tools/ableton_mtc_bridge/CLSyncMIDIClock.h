#ifndef CL_SYNC_MIDI_CLOCK_H
#define CL_SYNC_MIDI_CLOCK_H
#include <mach/mach_time.h>
static inline double CLSyncPacketTime(uint64_t stamp,double arrival) {
    if (!stamp) return arrival;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    uint64_t absolute=mach_absolute_time();
    double age=((double)absolute-(double)stamp)*tb.numer/tb.denom/1e9;
    return age>=0 && age<.5 ? arrival-age : arrival;
}
#endif

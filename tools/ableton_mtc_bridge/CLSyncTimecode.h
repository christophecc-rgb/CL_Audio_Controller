#ifndef CL_SYNC_TIMECODE_H
#define CL_SYNC_TIMECODE_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
/* Shared with CLSyncProbe: forward MTC at 25 fps, nominal correction +2 frames. */
static inline double wrapSeconds(
    double seconds
)
{
    while (seconds < 0.0) {
        seconds += 86400.0;
    }

    while (seconds >= 86400.0) {
        seconds -= 86400.0;
    }

    return seconds;
}


static inline double wrappedDifference(
    double a,
    double b
)
{
    double d = a - b;

    if (d > 43200.0) {
        d -= 86400.0;
    }

    if (d < -43200.0) {
        d += 86400.0;
    }

    return d;
}


static inline double tcToSeconds(
    int h,
    int m,
    int s,
    int f
)
{
    return
        (h * 3600.0) +
        (m * 60.0) +
        s +
        (f / 25.0);
}


static inline void secondsToTC(
    double seconds,
    int *h,
    int *m,
    int *s,
    int *f
)
{
    seconds =
        wrapSeconds(seconds);

    int totalFrames =
        (int)floor(
            seconds * 25.0 + 0.000001
        );

    *f = totalFrames % 25;

    int totalSeconds =
        totalFrames / 25;

    *s = totalSeconds % 60;
    *m = (totalSeconds / 60) % 60;
    *h = (totalSeconds / 3600) % 24;
}



static inline bool CLSyncDecodeQF(const uint8_t qf[8], double *corrected) {
    int f = qf[0] | ((qf[1] & 1) << 4);
    int s = qf[2] | ((qf[3] & 3) << 4);
    int m = qf[4] | ((qf[5] & 3) << 4);
    int h = qf[6] | ((qf[7] & 1) << 4);
    if (((qf[7] >> 1) & 3) != 1 || f >= 25 || s >= 60 || m >= 60 || h >= 24)
        return false;
    *corrected = wrapSeconds(tcToSeconds(h,m,s,f) + 2.0/25.0);
    return true;
}
#endif

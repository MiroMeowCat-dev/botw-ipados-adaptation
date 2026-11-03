#ifndef BOTW_MOTION_MATH_H
#define BOTW_MOTION_MATH_H
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
enum { BM_LANDSCAPE_RIGHT=3, BM_LANDSCAPE_LEFT=4 };
#define BM_MAX_SAMPLE_AGE_NS 50000000ull
// Core Motion uses portrait axes; Switch six-axis input uses screen axes.
// These are proper rotations (determinant +1), for acceleration AND angular rate.
static inline bool bm_landscape(int orientation,const double in[3],double out[3]) {
    if(orientation!=BM_LANDSCAPE_LEFT && orientation!=BM_LANDSCAPE_RIGHT)return false;
    const double x=in[0],y=in[1],z=in[2];
    out[0]=orientation==BM_LANDSCAPE_LEFT?y:-y;
    out[1]=orientation==BM_LANDSCAPE_LEFT?-x:x;out[2]=z;return true;
}
static inline bool bm_sample_fresh(double timestamp,uint64_t now) {
    if(!isfinite(timestamp) || timestamp<=0 || timestamp>18446744073.0)return false;
    uint64_t ns=(uint64_t)(timestamp*1e9);
    return ns<=now && now-ns<=BM_MAX_SAMPLE_AGE_NS;
}
static inline bool bm_vectors_valid(const double acc[3],const double rate[3]) {
    for(int i=0;i<3;i++)if(!isfinite(acc[i]) || !isfinite(rate[i]) || fabs(acc[i])>100 || fabs(rate[i])>100)return false;
    return true;
}
#endif

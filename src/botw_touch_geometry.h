#pragma once
#include <math.h>

// Pure geometry shared by the iOS editor and host-side boundary tests.
static inline double botw_clamp(double v, double lo, double hi, double fallback) {
    if (!isfinite(v)) v = fallback;
    if (hi < lo) return (lo + hi) * .5;
    return v < lo ? lo : v > hi ? hi : v;
}
static inline double botw_control_center(double normalized, double start, double length, double radius) {
    return botw_clamp(start + botw_clamp(normalized, 0, 1, .5) * length,
                      start + radius, start + length - radius, start + length * .5);
}
static inline double botw_normalized(double point, double start, double length) {
    return length > 0 ? botw_clamp((point - start) / length, 0, 1, .5) : .5;
}

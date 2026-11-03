#ifndef BOTW_INVENTORY_DETECTOR_H
#define BOTW_INVENTORY_DETECTOR_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

// Measured inventory mask: 15,315,1050,600 in the 1920x1080 canvas.
// In fullscreen the existing host compresses Y around canvas centre. Match both
// forms so recognition remains active after switching the menu back to 16:9.
static inline bool botw_inventory_scissor(uint64_t x, uint64_t y, uint64_t w, uint64_t h) {
    if(x>4096 || y>4096 || w>4096 || h>4096)return false;
    const double ratio = (16.0/9.0)/(2420.0/1668.0);
    for (int size=0; size<2; size++) {
        const double scale = size ? 1280.0/1920.0 : 1.0;
        const double cy = 540*scale;
        for (int squeezed=0; squeezed<2; squeezed++) {
            double y0=315*scale, y1=915*scale;
            if (squeezed) { y0=cy+(y0-cy)/ratio; y1=cy+(y1-cy)/ratio; }
            if (fabs((double)x-15*scale)<=3 && fabs((double)w-1050*scale)<=3 &&
                fabs((double)y-round(y0))<=3 && fabs((double)(y+h)-round(y1))<=3) return true;
        }
    }
    return false;
}
#endif

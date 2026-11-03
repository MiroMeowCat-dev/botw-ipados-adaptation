#include "botw_touch_geometry.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void require(int condition, const char *message) {
    checks++;
    if (!condition) {fprintf(stderr,"FAIL: %s\n",message);exit(1);}
}
int main(void) {
    require(botw_clamp(NAN,0,1,.5)==.5,"corrupted NaN preference");
    require(botw_clamp(INFINITY,.65,1.8,1)==1,"infinite size preference");
    require(botw_normalized(0,0,0)==.5,"zero-sized window");
    require(botw_normalized(-500,12,1000)==0,"drag beyond left edge");
    require(botw_normalized(5000,12,1000)==1,"drag beyond right edge");
    // Landscape/portrait/resized iPad windows, rounded corners and home bar.
    const double lengths[]={1210,834,600,400,80,1};
    const double radii[]={15,23,42,70,105};
    const double normalized[]={-1,0,.01,.14,.5,.86,.99,1,2,NAN,INFINITY};
    for(unsigned w=0;w<sizeof(lengths)/sizeof(*lengths);w++)
      for(unsigned r=0;r<sizeof(radii)/sizeof(*radii);r++)
        for(unsigned n=0;n<sizeof(normalized)/sizeof(*normalized);n++) {
            double p=botw_control_center(normalized[n],16,lengths[w],radii[r]);
            require(isfinite(p),"finite control coordinates after resize");
            if(lengths[w]>=2*radii[r]) {
                require(p>=16+radii[r] && p<=16+lengths[w]-radii[r],"whole control inside safe area");
                double saved=botw_normalized(p,16,lengths[w]);
                double replay=botw_control_center(saved,16,lengths[w],radii[r]);
                require(fabs(p-replay)<1e-8,"save/reload position round trip");
            } else require(fabs(p-(16+lengths[w]/2))<1e-8,"oversized control centers in small window");
        }
    double saved=botw_normalized(1080,16,1178);
    double resized=botw_control_center(saved,16,568,30);
    require(resized>=46 && resized<=554,"normalized position survives window resizing");
    printf("{\"geometry_checks_passed\":%u,\"uikit_runtime_tested\":false}\n",checks);
    return 0;
}

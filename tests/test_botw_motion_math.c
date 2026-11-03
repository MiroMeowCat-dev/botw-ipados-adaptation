#include <assert.h>
#include <stdio.h>
#include "botw_motion_math.h"
static unsigned checks;
#define CHECK(x) do{assert(x);checks++;}while(0)
static double dot(const double a[3],const double b[3]){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
static void cross(const double a[3],const double b[3],double c[3]){c[0]=a[1]*b[2]-a[2]*b[1];c[1]=a[2]*b[0]-a[0]*b[2];c[2]=a[0]*b[1]-a[1]*b[0];}
int main(void){
    double x[3]={1,0,0},y[3]={0,1,0},z[3]={0,0,1},a[3],b[3],c[3],d[3];
    for(int o=3;o<=4;o++){
        CHECK(bm_landscape(o,x,a));CHECK(bm_landscape(o,y,b));CHECK(bm_landscape(o,z,c));
        CHECK(dot(a,a)==1 && dot(b,b)==1 && dot(c,c)==1);
        CHECK(dot(a,b)==0 && dot(a,c)==0 && dot(b,c)==0);
        cross(a,b,d);CHECK(dot(d,c)==1); // no reflection of angular-velocity handedness
        double g[3]={0,0,-1};CHECK(bm_landscape(o,g,a));CHECK(a[2]==-1 && dot(a,a)==1);
    }
    CHECK(bm_landscape(3,x,a) && a[1]==1);CHECK(bm_landscape(4,x,a) && a[1]==-1);
    CHECK(!bm_landscape(1,x,a));CHECK(!bm_landscape(0,x,a));
    CHECK(bm_sample_fresh(1.0,1000000000ull));
    CHECK(bm_sample_fresh(1.0,1050000000ull));
    CHECK(!bm_sample_fresh(1.0,1050000001ull));
    CHECK(!bm_sample_fresh(1.1,1000000000ull));
    CHECK(!bm_sample_fresh(NAN,1000000000ull));CHECK(!bm_sample_fresh(INFINITY,1000000000ull));
    CHECK(!bm_sample_fresh(0,1000000000ull));CHECK(!bm_sample_fresh(-1,1000000000ull));
    CHECK(!bm_sample_fresh(1e30,1000000000ull));
    CHECK(bm_vectors_valid(x,y));
    a[0]=NAN;a[1]=a[2]=0;CHECK(!bm_vectors_valid(a,y));
    a[0]=INFINITY;CHECK(!bm_vectors_valid(x,a));
    a[0]=101;CHECK(!bm_vectors_valid(a,y));
    a[0]=100;CHECK(bm_vectors_valid(a,y));
    printf("{\"checks\":%u,\"proper_rotation_both_landscapes\":true,\"stale_future_nonfinite_rejected\":true}\n",checks);
}

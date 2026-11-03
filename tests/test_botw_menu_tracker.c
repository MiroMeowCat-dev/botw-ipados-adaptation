#include <assert.h>
#include <stdio.h>
#include "botw_menu_tracker.h"
static unsigned checks;
#define CHECK(x) do { assert(x);checks++; } while(0)
static BotWMenuTracker opened(void) {
    BotWMenuTracker s={0};
    botw_menu_step(&s,10,1,1000000000ull);
    CHECK(!s.inventory);
    botw_menu_step(&s,11,1,1010000000ull);
    CHECK(s.inventory);return s;
}
int main(void) {
    BotWMenuFrames r={0};
    CHECK(botw_menu_observation(&r,0)==-1);
    botw_menu_observe(&r,0,false);CHECK(botw_menu_observation(&r,0)==0);
    botw_menu_observe(&r,0,true);botw_menu_observe(&r,0,false);
    CHECK(botw_menu_observation(&r,0)==1);
    botw_menu_observe(&r,64,false);botw_menu_observe(&r,0,true);
    CHECK(botw_menu_observation(&r,0)==-1);CHECK(botw_menu_observation(&r,64)==0);
    botw_menu_observe(&r,UINT64_MAX,true);CHECK(botw_menu_observation(&r,UINT64_MAX)==-1);
    for(unsigned fps=30;fps<=120;fps*=2) {
        BotWMenuTracker s=opened();uint64_t start=1100000000ull,step=1000000000ull/fps;
        unsigned n=0;
        while(s.inventory && n<20){botw_menu_step(&s,12+n,0,start+n*step);n++;}
        CHECK(!s.inventory);CHECK(n>=3);
        CHECK((n-1)*step>=BOTW_MENU_EXIT_MIN_NS);
        CHECK((n-1)*step<120000000ull);
    }
    BotWMenuTracker s=opened();
    botw_menu_step(&s,12,0,1100000000ull);
    botw_menu_step(&s,13,0,1200000000ull);CHECK(s.inventory);
    botw_menu_step(&s,14,1,1300000000ull);CHECK(s.inventory && s.absentFrames==0);
    // A frozen game is not a closed inventory, even after a long wall-clock wait.
    botw_menu_step(&s,14,0,9000000000ull);CHECK(s.inventory);
    botw_menu_step(&s,15,0,9010000000ull);
    botw_menu_step(&s,16,-1,9110000000ull);
    botw_menu_step(&s,17,0,9210000000ull);CHECK(s.inventory && s.absentFrames==1);
    botw_menu_step(&s,30,0,9310000000ull);CHECK(s.inventory && s.absentFrames==1);
    botw_menu_reset_evidence(&s);CHECK(s.inventory && !s.haveFrame);
    botw_menu_step(&s,100,0,9400000000ull);CHECK(s.inventory);
    botw_menu_step(&s,101,0,9430000000ull);CHECK(s.inventory);
    botw_menu_step(&s,102,0,9460000000ull);CHECK(!s.inventory);
    // Isolated hits and out-of-order observations cannot trigger entry.
    s=(BotWMenuTracker){0};
    botw_menu_step(&s,1,1,1);botw_menu_step(&s,2,0,2);botw_menu_step(&s,3,1,3);
    CHECK(!s.inventory);botw_menu_step(&s,2,1,4);CHECK(!s.inventory);
    botw_menu_step(&s,4,1,5);CHECK(s.inventory);
    printf("{\"checks\":%u,\"tested_fps\":[30,60,120],\"unknown_frames_hold_state\":true,\"stalled_game_holds_state\":true,\"ring_positive_wins\":true}\n",checks);
}

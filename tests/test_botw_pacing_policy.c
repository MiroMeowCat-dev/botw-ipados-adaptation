#include <assert.h>
#include <stdio.h>
#include "botw_pacing_policy.h"
static unsigned checks;
#define CHECK(x) do{assert(x);checks++;}while(0)
// Matches the pinned present_ticks normal path: DISPLAY is 1 tick; GAME uses
// the game's interval. Movie/held-30 paths remain in the unmodified host.
static double normal_period(BotWPacingPolicy p,int game_interval) {
    int ticks=p.display_interval?1:game_interval;
    return (double)ticks/p.target_hz;
}
int main(void) {
    CHECK(botw_pacing_policy(0).target_hz==0 && !botw_pacing_policy(0).display_interval);
    CHECK(botw_pacing_policy(-1).target_hz==0);
    CHECK(botw_pacing_policy(120).target_hz==0);
    for(int hz=30;hz<=60;hz+=30){
        BotWPacingPolicy p=botw_pacing_policy(hz);CHECK(p.target_hz==hz);CHECK(p.display_interval);
        for(int interval=1;interval<=3;interval++)CHECK(normal_period(p,interval)==1.0/hz);
    }
    BotWPacingPolicy old={60,false};CHECK(normal_period(old,2)==1.0/30);
    old=(BotWPacingPolicy){30,false};CHECK(normal_period(old,2)==1.0/15);
    printf("{\"checks\":%u,\"old_60_to_30_model_regression_reproduced\":true,\"generic_30hz_double_interval_model_verified\":true,\"display_tick_cap_independent_of_game_interval\":true,\"auto_preserved\":true}\n",checks);
}

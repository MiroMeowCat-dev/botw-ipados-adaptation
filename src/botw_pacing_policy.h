#ifndef BOTW_PACING_POLICY_H
#define BOTW_PACING_POLICY_H
#include <stdbool.h>
typedef struct { int target_hz; bool display_interval; } BotWPacingPolicy;
static inline BotWPacingPolicy botw_pacing_policy(int requested) {
    if(requested==30 || requested==60)return (BotWPacingPolicy){requested,true};
    return (BotWPacingPolicy){0,false}; // auto: preserve original host policy
}
#endif

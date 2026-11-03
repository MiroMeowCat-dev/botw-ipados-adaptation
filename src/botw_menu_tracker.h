#ifndef BOTW_MENU_TRACKER_H
#define BOTW_MENU_TRACKER_H
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

#define BOTW_MENU_RING_SIZE 64u
#define BOTW_MENU_EXIT_FRAMES 3u
#define BOTW_MENU_EXIT_MIN_NS 50000000ull

// A slot records an observed host encoding interval, not GPU completion.
// Multiple encoders may publish to one interval; a positive observation wins.
typedef struct { _Atomic uint64_t slots[BOTW_MENU_RING_SIZE]; } BotWMenuFrames;
static inline void botw_menu_observe(BotWMenuFrames *r, uint64_t frame, bool hit) {
    if (frame >= (UINT64_MAX >> 1) - 1) return;
    uint64_t tag=(frame+1)<<1, want=tag|(uint64_t)hit;
    _Atomic uint64_t *slot=&r->slots[frame % BOTW_MENU_RING_SIZE];
    uint64_t old=atomic_load_explicit(slot,memory_order_relaxed);
    for (;;) {
        if ((old & ~1ull)>tag || old==want || old==(tag|1ull)) return;
        if (atomic_compare_exchange_weak_explicit(slot,&old,want,memory_order_release,memory_order_relaxed)) return;
    }
}
// -1 is unobserved/overwritten. It must never count as evidence of menu exit.
static inline int botw_menu_observation(const BotWMenuFrames *r, uint64_t frame) {
    if (frame >= (UINT64_MAX >> 1) - 1) return -1;
    uint64_t v=atomic_load_explicit(&r->slots[frame % BOTW_MENU_RING_SIZE],memory_order_acquire);
    return (v & ~1ull)==((frame+1)<<1) ? (int)(v&1) : -1;
}
typedef struct {
    uint64_t frame, firstAbsentNS, lastPositiveNS;
    unsigned positiveFrames, absentFrames;
    bool haveFrame, inventory;
} BotWMenuTracker;
static inline void botw_menu_reset_evidence(BotWMenuTracker *s) {
    s->haveFrame=false;s->positiveFrames=0;s->absentFrames=0;s->firstAbsentNS=0;
    // Preserve the displayed state across a stall, backgrounding or missing data.
}
static inline void botw_menu_step(BotWMenuTracker *s,uint64_t frame,int observation,uint64_t now) {
    if (s->haveFrame && frame<=s->frame) return;
    bool adjacent=s->haveFrame && frame-s->frame==1;
    if (!adjacent) { s->positiveFrames=0;s->absentFrames=0;s->firstAbsentNS=0; }
    s->haveFrame=true;s->frame=frame;
    if (observation<0) {s->positiveFrames=0;s->absentFrames=0;s->firstAbsentNS=0;return;}
    if (observation) {
        if(s->positiveFrames<2)s->positiveFrames++;
        s->absentFrames=0;s->firstAbsentNS=0;s->lastPositiveNS=now;
        if(s->positiveFrames>=2)s->inventory=true;
    } else {
        s->positiveFrames=0;
        if(!s->absentFrames)s->firstAbsentNS=now;
        if(s->absentFrames<UINT32_MAX)s->absentFrames++;
        if(s->absentFrames>=BOTW_MENU_EXIT_FRAMES && now>=s->firstAbsentNS &&
           now-s->firstAbsentNS>=BOTW_MENU_EXIT_MIN_NS)s->inventory=false;
    }
}
#endif

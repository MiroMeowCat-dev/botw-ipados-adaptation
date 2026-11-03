// Local, user-triggered two-frame canvas trace for this pinned host only.
// No networking, credentials, input injection, or executable-memory writes.
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>
#include <stdint.h>
#include "inventory_probe_host.h"

typedef void (*FlagSetter)(const char *, int);
static FlagSetter setter;
static BOOL guardChecked;
#ifndef BOTW_UNIFIED_SETTINGS
static UIButton *entry;
#endif
static unsigned captures;
#ifdef BOTW_MENU_COMPAT
static void compatAttach(void);
static void compatTick(void);
#endif

static FlagSetter checkedSetter(void) {
    if (guardChecked) return setter;
    guardChecked = YES;
    const struct mach_header_64 *h = (const void *)_dyld_get_image_header(0);
    if (!h || h->magic != MH_MAGIC_64 || h->cputype != CPU_TYPE_ARM64 ||
        h->ncmds > 1024 || h->sizeofcmds > 16384) return NULL;
    const uint8_t *at = (const uint8_t *)(h+1), *end = at+h->sizeofcmds;
    BOOL uuidOK = NO;
    for (uint32_t i=0; i<h->ncmds; i++) {
        if ((size_t)(end-at) < sizeof(struct load_command)) return NULL;
        const struct load_command *c = (const void *)at;
        if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end-at)) return NULL;
        if (c->cmd == LC_UUID && c->cmdsize == sizeof(struct uuid_command))
            uuidOK = memcmp(((const struct uuid_command *)c)->uuid, HostUUID, sizeof HostUUID) == 0;
        at += c->cmdsize;
    }
    if (!uuidOK) return NULL;
    const uint8_t *fn = (const void *)(HostFlagAddress + (uintptr_t)_dyld_get_image_vmaddr_slide(0));
    if (memcmp(fn, HostFlagSignature, sizeof HostFlagSignature)) return NULL;
    setter = (FlagSetter)(uintptr_t)fn;
    return setter;
}

static void report(NSString *state) {
    NSURL *docs = [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    if (!docs) return;
    NSURL *dir = [docs URLByAppendingPathComponent:@"Tuning" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *r = @{@"build":
#ifdef BOTW_MENU_COMPAT
        BOTW_COMPAT_BUILD,
#else
        @"inventory-probe-v5",
#endif
        @"status":state,
        @"captures_this_launch":@(captures), @"frames_per_capture":@2,
        @"host_guard_passed":@(setter != NULL), @"networking":@NO,
        @"automatic_capture":@NO, @"rendering_changed":@NO,
        @"time_unix":@([NSDate.date timeIntervalSince1970])};
    NSData *data = [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:[dir URLByAppendingPathComponent:@"inventory-probe-v1.json"] options:NSDataWritingAtomic error:nil];
}

@interface BotWInventoryProbe : NSObject
+ (void)capture:(UIButton *)sender;
@end
#ifdef BOTW_MENU_COMPAT
@interface BotWInventoryProbe (Compatibility)
+ (void)menu:(UIButton *)sender;
@end
#endif
@implementation BotWInventoryProbe
+ (void)capture:(UIButton *)sender {
    FlagSetter fn = checkedSetter();
    if (!fn) { [sender setTitle:@"版本不匹配" forState:UIControlStateNormal]; report(@"host_guard_failed"); return; }
    if (captures >= 4) { [sender setTitle:@"本次记录已足够" forState:UIControlStateNormal]; return; }
    captures++;
    sender.enabled = NO;
    [sender setTitle:@"记录中…" forState:UIControlStateNormal];
    // The existing host API stores an atomic frame counter, consumed by present.
    fn("uw_log", 2);
#ifdef BOTW_MENU_COMPAT
    fn("draw_log", 2); // Also works when the 16:9 path does not learn a canvas.
#endif
    report(@"two_frame_canvas_capture_requested");
    // A second bound also disables logging if no game frames were presented.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        fn("uw_log", 0);
#ifdef BOTW_MENU_COMPAT
        fn("draw_log", 0);
#endif
        [sender setTitle:@"记录完成" forState:UIControlStateNormal];
        sender.enabled = YES;
        report(@"capture_window_finished");
    });
}
@end

static void attach(void) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
#ifdef BOTW_UNIFIED_SETTINGS
    // The shared settings panel owns all UI. Compatibility must keep running
    // even when the user hides that panel's entry button.
    compatAttach();
#else
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.isKeyWindow || w.hidden || w.windowLevel != UIWindowLevelNormal) continue;
            if (!entry) {
                entry = [UIButton buttonWithType:UIButtonTypeSystem];
                [entry setTitle:
#ifdef BOTW_MENU_COMPAT
                    @"背包显示"
#else
                    @"记录背包"
#endif
                    forState:UIControlStateNormal];
                [entry setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
                entry.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
                entry.backgroundColor = [UIColor colorWithWhite:.08 alpha:.85];
                entry.layer.cornerRadius = 10;
                entry.accessibilityLabel =
#ifdef BOTW_MENU_COMPAT
                    @"背包画面兼容设置";
#else
                    @"记录两帧背包画面诊断信息";
#endif
                [entry addTarget:BotWInventoryProbe.class action:
#ifdef BOTW_MENU_COMPAT
                    @selector(menu:)
#else
                    @selector(capture:)
#endif
                    forControlEvents:UIControlEventTouchUpInside];
            }
            if (entry.superview != w) [w addSubview:entry];
            entry.frame = CGRectMake(CGRectGetMidX(w.bounds)+64, CGRectGetMaxY(w.bounds)-w.safeAreaInsets.bottom-44, 112, 34);
            [w bringSubviewToFront:entry];
#ifdef BOTW_MENU_COMPAT
            compatAttach();
#endif
            return;
        }
    }
#endif
}
__attribute__((constructor)) static void installProbe(void) {
    @autoreleasepool {
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n; attach();
        }];
#ifdef BOTW_UNIFIED_SETTINGS
        [NSNotificationCenter.defaultCenter addObserverForName:BOTW_SETTINGS_CHANGED object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){attach();}];
#endif
        for (int i=1; i<=3; i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i*NSEC_PER_SEC),dispatch_get_main_queue(),^{attach();});
#ifdef BOTW_MENU_COMPAT
        NSTimer *timer=[NSTimer timerWithTimeInterval:BOTW_COMPAT_POLL_SECONDS repeats:YES block:^(__unused NSTimer *t){compatTick();}];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
#endif
    }
}

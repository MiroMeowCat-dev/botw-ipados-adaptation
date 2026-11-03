// Automatic inventory compatibility through the host's original aspect toggle.
// Observes the public Metal scissor setter; never patches executable memory.
#define BOTW_MENU_COMPAT 1
#define BOTW_COMPAT_BUILD @"inventory-compat-v7"
#define BOTW_COMPAT_POLL_SECONDS (1.0/60.0)
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include "botw_settings_shared.h"
#include "botw_inventory_detector.h"
#include "botw_menu_tracker.h"
#include "inventory_compat_host.h"
#include "botw_inventory_probe.m"

typedef int (*AspectToggle)(void);
static AspectToggle toggleAspect;
static BOOL compatGuardChecked;
static NSString *const AutoKey=@"BOTW_MENU_COMPAT_ENABLED";
typedef void (*ScissorSetter)(id,SEL,MTLScissorRect);
static struct { Class cls; ScissorSetter original; } hooked[64];
static unsigned hookCount;
static pthread_rwlock_t hookLock=PTHREAD_RWLOCK_INITIALIZER;
static BotWMenuFrames observedFrames;
static BotWMenuTracker tracker;
static uint64_t consumedFrame, matchedFrames;
static BOOL haveConsumedFrame;
static NSMutableArray *transitions;
static dispatch_queue_t reportQueue;
static BOOL autoSession;
static NSInteger manualMode; // 0 automatic, 1 temporary 16:9, 2 temporary full
static uint64_t lastActiveNS;
static unsigned switches;

static uint64_t nowNS(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static BOOL compatReady(void) {
    if (compatGuardChecked) return toggleAspect!=NULL;
    compatGuardChecked=YES;
    if (!checkedSetter()) return NO;
    uintptr_t slide=(uintptr_t)_dyld_get_image_vmaddr_slide(0);
    const uint8_t *fn=(const void *)(HostToggleAddress+slide);
    if (memcmp(fn,HostToggleSignature,sizeof HostToggleSignature)) return NO;
    toggleAspect=(AspectToggle)(uintptr_t)fn;
    return YES;
}
static uint32_t actualOn(void) {
    return atomic_load_explicit((_Atomic uint32_t *)(HostOnAddress+(uintptr_t)_dyld_get_image_vmaddr_slide(0)),memory_order_acquire);
}
static float hostRatio(void) {
    float ratio;
    memcpy(&ratio,(const void *)(HostWideAddress+(uintptr_t)_dyld_get_image_vmaddr_slide(0)),sizeof ratio);
    return ratio;
}
static void noteScissor(MTLScissorRect r) {
    uint64_t frame=atomic_load_explicit((_Atomic uint64_t *)(HostFrameAddress+(uintptr_t)_dyld_get_image_vmaddr_slide(0)),memory_order_acquire);
    botw_menu_observe(&observedFrames,frame,botw_inventory_scissor(r.x,r.y,r.width,r.height));
}
static void hookedScissor(id obj,SEL sel,MTLScissorRect r) {
    // The saved IMP never changes after publication. Avoid a read lock and
    // hierarchy walk on every draw once this thread has seen an encoder class.
    static _Thread_local Class cachedClass;
    static _Thread_local ScissorSetter cachedOriginal;
    Class cls=object_getClass(obj);ScissorSetter old=cachedOriginal;
    if(cls!=cachedClass || !old) {
        old=NULL;pthread_rwlock_rdlock(&hookLock);
        for (Class c=cls;c&&!old;c=class_getSuperclass(c))
            for (unsigned i=0;i<hookCount;i++) if(hooked[i].cls==c){old=hooked[i].original;break;}
        pthread_rwlock_unlock(&hookLock);
        cachedClass=cls;cachedOriginal=old;
    }
    // The map is published before method replacement; every intercepted method
    // has an original. Do not modify the viewport or the scissor itself.
    if (old) { noteScissor(r); old(obj,sel,r); }
}
static void installScissorHooks(void) {
    if (!compatReady()) return;
    unsigned count=0;Class *classes=objc_copyClassList(&count);if(!classes)return;
    SEL scissor=@selector(setScissorRect:);
    struct {Class cls;Method method;} candidates[128];unsigned nCandidates=0;
    for(unsigned i=0;i<count;i++) {
        Class cls=classes[i];
        if (!class_getInstanceMethod(cls,@selector(setViewport:)) || !class_getInstanceMethod(cls,@selector(endEncoding))) continue;
        unsigned n=0;Method *methods=class_copyMethodList(cls,&n);
        for(unsigned k=0;k<n;k++) {
            Method m=methods[k]; if(method_getName(m)!=scissor || method_getNumberOfArguments(m)!=3)continue;
            char *arg=method_copyArgumentType(m,2), *ret=method_copyReturnType(m);NSUInteger bytes=0;
            if(arg && arg[0]=='{')NSGetSizeAndAlignment(arg,&bytes,NULL);
            BOOL shape=arg&&ret&&ret[0]=='v'&&bytes==sizeof(MTLScissorRect);free(arg);free(ret);if(!shape)continue;
            if(nCandidates<128){candidates[nCandidates].cls=cls;candidates[nCandidates].method=m;nCandidates++;}
        }
        free(methods);
    }
    free(classes);
    // Never intercept both a class and its ancestor: an original implementation
    // may call super, which would otherwise re-enter the same saved IMP.
    for(unsigned i=0;i<nCandidates;i++) {
        Class cls=candidates[i].cls;BOOL ancestor=NO;
        for(unsigned j=0;j<nCandidates;j++)if(i!=j)
            for(Class c=class_getSuperclass(candidates[j].cls);c;c=class_getSuperclass(c))if(c==cls)ancestor=YES;
        if(ancestor)continue;
        pthread_rwlock_wrlock(&hookLock);
        Method m=candidates[i].method;IMP original=method_getImplementation(m);BOOL known=original==(IMP)hookedScissor;
        for(unsigned j=0;j<hookCount;j++) {
            for(Class c=cls;c;c=class_getSuperclass(c))if(c==hooked[j].cls)known=YES;
            for(Class c=hooked[j].cls;c;c=class_getSuperclass(c))if(c==cls)known=YES;
        }
        if(!known&&original&&hookCount<64){hooked[hookCount].cls=cls;hooked[hookCount].original=(ScissorSetter)original;hookCount++;method_setImplementation(m,(IMP)hookedScissor);}
        pthread_rwlock_unlock(&hookLock);
    }
}
static void reportCompat(NSString *reason) {
#ifdef BOTW_UNIFIED_SETTINGS
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"BOTW_IPAD_LOCAL_DIAGNOSTICS"])return;
#endif
    NSURL *docs=[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];if(!docs)return;
    NSURL *dir=[docs URLByAppendingPathComponent:@"Tuning" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    pthread_rwlock_rdlock(&hookLock);unsigned hooks=hookCount;pthread_rwlock_unlock(&hookLock);
    NSDictionary *r=@{@"build":BOTW_COMPAT_BUILD,@"reason":reason,@"host_guard_passed":@(toggleAspect!=NULL),
        @"hooked_encoder_classes":@(hooks),@"matched_inventory_frames":@(matchedFrames),
        @"last_inventory_observed_ns":@(tracker.lastPositiveNS),@"aspect_toggle_count":@(switches),
        @"exit_absent_observed_frames":@(tracker.absentFrames),@"exit_min_absent_ms":@50,
        @"exit_required_absent_frames":@BOTW_MENU_EXIT_FRAMES,@"poll_target_ms":@(1000.0*BOTW_COMPAT_POLL_SECONDS),
        @"host_encoding_interval_lag":@2,@"gpu_completion_observed":@NO,
        @"transition_history":transitions?:@[],
        @"actual_aspect_enabled":@(actualOn()),@"host_fullscreen_ratio":@(hostRatio()),
        @"auto_session_active":@(autoSession),@"manual_mode":@(manualMode),@"networking":@NO,
        @"host_cpu_instructions_modified":@NO,@"scissor_or_viewport_modified":@NO,@"time_unix":@([NSDate.date timeIntervalSince1970])};
    NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil];
    if(!reportQueue)reportQueue=dispatch_queue_create("local.botw.menu-report",DISPATCH_QUEUE_SERIAL);
    NSURL *file=[dir URLByAppendingPathComponent:@"menu-compat-v1.json"];
    dispatch_async(reportQueue,^{[data writeToURL:file options:NSDataWritingAtomic error:nil];});
}
static void setAspect(BOOL on,NSString *reason) {
    if(!compatReady())return;
    uint32_t current=actualOn();if(current>1 || (BOOL)current==on)return;
    // The original function atomically updates its enable flag and camera data
    // word. Its normal frame path restores the original camera and presenter.
    if(toggleAspect()) {
        switches++;
        if(!transitions)transitions=[NSMutableArray new];
        uint64_t now=nowNS();
        [transitions addObject:@{@"to_fullscreen":@(on),@"reason":reason,@"host_frame":@(consumedFrame),
            @"monotonic_ns":@(now),@"absent_frames":@(tracker.absentFrames),
            @"observed_absence_ms":@(tracker.firstAbsentNS && now>=tracker.firstAbsentNS?(now-tracker.firstAbsentNS)/1e6:0)}];
        if(transitions.count>32)[transitions removeObjectAtIndex:0];
        reportCompat(reason);
    }
}
static void compatAttach(void) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{AutoKey:@YES}];
#ifdef BOTW_UNIFIED_SETTINGS
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    NSString *mode=[prefs stringForKey:BOTW_MENU_MODE_KEY];
    // Missing new key adopts the old automatic-compatibility preference.
    manualMode=[mode isEqualToString:@"16:9"]?1:[mode isEqualToString:@"fullscreen"]?2:
        (!mode && ![prefs boolForKey:AutoKey])?2:0;
#endif
    installScissorHooks();
    if(!compatReady())return;
    autoSession=fabsf(hostRatio()-(2420.0f/1668.0f))<.001f;
    reportCompat(@"controls_attached");
}
static void compatTick(void) {
    if(!compatReady())return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){lastActiveNS=0;return;}
    uint64_t now=nowNS();
    uint64_t current=atomic_load_explicit((_Atomic uint64_t *)(HostFrameAddress+(uintptr_t)_dyld_get_image_vmaddr_slide(0)),memory_order_acquire);
    BOOL stale=lastActiveNS==0 || now-lastActiveNS>250000000ull;
    lastActiveNS=now;
    if(stale || !haveConsumedFrame || current<consumedFrame) {
        // Do not replay old render observations after backgrounding or a long
        // main-thread stall. Wait for fresh encoding intervals before changing.
        botw_menu_reset_evidence(&tracker);
        consumedFrame=current>1?current-2:0;haveConsumedFrame=current>1;
        if(manualMode==0)return;
    }
    // g_cur_frame is set by the host at mtl_set_frame(), not a GPU-completion
    // event. Leave the current and immediately preceding interval untouched.
    if(current>1 && haveConsumedFrame && current-2>consumedFrame) {
        uint64_t end=current-2;
        if(end-consumedFrame>=BOTW_MENU_RING_SIZE) {
            botw_menu_reset_evidence(&tracker);consumedFrame=end-1;
        }
        for(uint64_t f=consumedFrame+1;f<=end;f++) {
            int observation=botw_menu_observation(&observedFrames,f);
            if(observation==1)matchedFrames++;
            botw_menu_step(&tracker,f,observation,now);
        }
        consumedFrame=end;
    }
    if(fabsf(hostRatio()-(2420.0f/1668.0f))<.001f)autoSession=YES;
    BOOL desired=actualOn()!=0;
    if(manualMode==1)desired=NO;
    else if(manualMode==2 && autoSession)desired=YES;
    else if(autoSession && manualMode==0
#ifndef BOTW_UNIFIED_SETTINGS
            && [NSUserDefaults.standardUserDefaults boolForKey:AutoKey]
#endif
            ) {
        desired=!tracker.inventory;
        // A fresh match in either unconsumed interval vetoes a stale exit.
        // It does not by itself enter compatibility (two positive frames needed).
        if(desired && !actualOn() && (botw_menu_observation(&observedFrames,current)==1 ||
           (current && botw_menu_observation(&observedFrames,current-1)==1)))desired=NO;
    }
    setAspect(desired,desired?@"world_fullscreen_restored":@"inventory_16_9_compatibility");
#ifndef BOTW_UNIFIED_SETTINGS
    if(entry.enabled)[entry setTitle:actualOn()?@"背包显示":@"背包16:9" forState:UIControlStateNormal];
#endif
}
#ifndef BOTW_UNIFIED_SETTINGS
@implementation BotWInventoryProbe (Compatibility)
+ (void)menu:(UIButton *)sender {
    UIViewController *vc=sender.window.rootViewController;while(vc.presentedViewController)vc=vc.presentedViewController;
    if(!vc)return;
    NSString *hint=autoSession?@"自动：背包使用16:9，退出后恢复全屏。手动选项仅影响本次运行。":@"本次按系统设置以16:9启动。要启用全屏自动兼容，保存全屏选项后彻底退出重开一次。";
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"背包显示" message:hint preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"自动兼容背包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){manualMode=0;[NSUserDefaults.standardUserDefaults setBool:YES forKey:AutoKey];compatTick();}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"临时切到16:9" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){manualMode=1;setAspect(NO,@"manual_16_9");}]];
    [menu addAction:[UIAlertAction actionWithTitle:autoSession?@"恢复全屏（本次手动）":@"保存全屏，下次启动生效" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        if(autoSession){manualMode=2;setAspect(YES,@"manual_fullscreen");}
        else{[NSUserDefaults.standardUserDefaults setObject:@"screen" forKey:@"BOTW_IPAD_ASPECT"];[NSUserDefaults.standardUserDefaults synchronize];}
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"记录画面（诊断）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/5),dispatch_get_main_queue(),^{[self capture:sender];});}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView=sender;menu.popoverPresentationController.sourceRect=sender.bounds;
    [vc presentViewController:menu animated:YES completion:nil];
}
@end
#endif

// iPad sensor -> the pinned host's existing six-axis fusion. No camera-stick emulation.
// The host exposes its generic feed only as runtime_motion_feed_mouse in this build.
// That historical API name does not mean that physical mouse input is generated.
#import <CoreMotion/CoreMotion.h>
#include "botw_motion_math.h"
#include "motion_host.h"
#include "botw_settings_shared.h"

typedef void (*BMFeed)(const double[3],const double[3],uint64_t);
typedef void (*BMOwner)(int);
typedef void (*BMReset)(void);
typedef uint64_t (*BMClock)(void);
typedef void (*BMStats)(uint64_t *,uint64_t *);
static BMFeed bmFeed;static BMOwner bmOwner;static BMReset bmReset;static BMClock bmClock;static BMStats bmStats;
static NSString *const BMEnableKey=@"BOTW_IPAD_GYRO_ENABLED";
static dispatch_queue_t bmQueue,bmReportQueue;
static dispatch_source_t bmTimer;
static CMMotionManager *bmManager;
static BOOL bmRunning,bmOwned;
static int bmOrientation;
static uint64_t bmFed,bmDistinct,bmRejected,bmLastFeed,bmBegan,bmLastReport;
static double bmLastTimestamp;
static NSString *bmState=@"not_started";

_Static_assert(BM_LANDSCAPE_LEFT==UIInterfaceOrientationLandscapeLeft && BM_LANDSCAPE_RIGHT==UIInterfaceOrientationLandscapeRight,"UIKit orientation values");
static BOOL bmReady(void) {
    static BOOL checked;if(checked)return bmFeed!=NULL;checked=YES;
    if(!checkedSetter())return NO;
    uintptr_t slide=(uintptr_t)_dyld_get_image_vmaddr_slide(0);
#define BM_BIND(name,type) do{const uint8_t *p=(const void *)(BM##name##Address+slide);if(memcmp(p,BM##name##Signature,32))return NO;}while(0)
    BM_BIND(Feed,BMFeed);BM_BIND(Owner,BMOwner);BM_BIND(Reset,BMReset);BM_BIND(Clock,BMClock);BM_BIND(Stats,BMStats);
#undef BM_BIND
    bmFeed=(BMFeed)(BMFeedAddress+slide);bmOwner=(BMOwner)(BMOwnerAddress+slide);
    bmReset=(BMReset)(BMResetAddress+slide);bmClock=(BMClock)(BMClockAddress+slide);bmStats=(BMStats)(BMStatsAddress+slide);
    return YES;
}
// All fusion ownership and sensor reads below run on this one serial queue.
static void bmWriteReport(void) {
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"BOTW_IPAD_LOCAL_DIAGNOSTICS"])return;
    uint64_t values=0,reads=0;if(bmStats)bmStats(&values,&reads);
    uint64_t now=bmClock?bmClock():0;
    NSDictionary *r=@{@"build":@"ipad-motion-v8",@"bundle_version":NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]?:@"unknown",
        @"host_guard_passed":@(bmFeed!=NULL),@"state":bmState,@"sensor_running":@(bmRunning),@"owns_six_axis_feed":@(bmOwned),
        @"orientation":@(bmOrientation),@"bridge_states_fed":@(bmFed),@"distinct_device_samples":@(bmDistinct),
        @"rejected_or_stale_ticks":@(bmRejected),@"game_motion_read_calls":@(reads),
        @"target_bridge_interval_ms":@5,@"hardware_rate_is_not_measured_by_bridge_rate":@YES,
        @"sensor_available":@(bmManager.deviceMotionAvailable),@"sensor_active":@(bmManager.deviceMotionActive),
        @"latest_sensor_timestamp":@(bmLastTimestamp),@"host_monotonic_ns":@(now),
        @"networking":@NO,@"raw_motion_history_recorded":@NO,@"executable_memory_writes":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil];
    dispatch_async(bmReportQueue,^{@autoreleasepool{
        NSURL *docs=[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
        NSURL *dir=[docs URLByAppendingPathComponent:@"Tuning" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:[dir URLByAppendingPathComponent:@"motion-v1.json"] options:NSDataWritingAtomic error:nil];
    }});
}
static void bmRelease(void) {if(bmOwned){bmOwner(0);bmOwned=NO;}bmLastFeed=0;}
static void bmStop(NSString *reason) {
    if(bmRunning)[bmManager stopDeviceMotionUpdates];bmRunning=NO;
    dispatch_source_set_timer(bmTimer,DISPATCH_TIME_FOREVER,5*NSEC_PER_MSEC,NSEC_PER_MSEC);
    bmRelease();bmState=reason;bmWriteReport();
}
static void bmTick(void) {
    if(!bmRunning)return;
    uint64_t now=bmClock();CMDeviceMotion *m=bmManager.deviceMotion;
    BOOL fresh=m && bm_sample_fresh(m.timestamp,now);
    double deviceAcc[3]={0},deviceRate[3]={0},acc[3],rate[3];
    if(fresh){
        CMAcceleration g=m.gravity,u=m.userAcceleration;CMRotationRate w=m.rotationRate;
        deviceAcc[0]=g.x+u.x;deviceAcc[1]=g.y+u.y;deviceAcc[2]=g.z+u.z;
        deviceRate[0]=w.x;deviceRate[1]=w.y;deviceRate[2]=w.z;
        fresh=bm_vectors_valid(deviceAcc,deviceRate) && bm_landscape(bmOrientation,deviceAcc,acc) && bm_landscape(bmOrientation,deviceRate,rate);
    }
    if(!fresh){
        bmRejected++;
        if(bmOwned && bmLastFeed && now-bmLastFeed>BM_MAX_SAMPLE_AGE_NS){bmRelease();bmState=@"waiting_for_fresh_sample";bmWriteReport();}
    } else {
        if(!bmOwned){bmOwner(1);bmOwned=YES;bmReset();bmState=@"feeding_device_motion";}
        // The old host has no console-clock resampler. Hold a fresh fused sample
        // until the next one on a 5 ms bridge clock, never beyond 50 ms of age.
        // This is rate integration for six-axis input, not new hardware samples.
        bmFeed(acc,rate,now);bmFed++;bmLastFeed=now;
        if(m.timestamp!=bmLastTimestamp){bmDistinct++;bmLastTimestamp=m.timestamp;}
    }
    if(!bmLastReport || (now-bmBegan<60000000000ull && now-bmLastReport>=2000000000ull)){
        bmLastReport=now;bmWriteReport();
    }
}
static void bmConfigure(BOOL active,BOOL enabled,int orientation) {
    if(!active || !enabled || (orientation!=BM_LANDSCAPE_LEFT && orientation!=BM_LANDSCAPE_RIGHT)){
        NSString *reason=!active?@"background":!enabled?@"disabled":@"waiting_for_landscape";
        if(bmRunning || ![bmState isEqualToString:reason])bmStop(reason);return;
    }
    if(bmRunning && bmOrientation==orientation)return;
    if(bmRunning)bmStop(@"orientation_changed");bmOrientation=orientation;
    if(!bmManager)bmManager=[CMMotionManager new];
    if(!bmManager.deviceMotionAvailable || !([CMMotionManager availableAttitudeReferenceFrames]&CMAttitudeReferenceFrameXArbitraryZVertical)){
        if(![bmState isEqualToString:@"sensor_unavailable"]){bmState=@"sensor_unavailable";bmWriteReport();}return;
    }
    bmManager.deviceMotionUpdateInterval=.005;
    [bmManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
    bmRunning=YES;bmLastTimestamp=0;bmBegan=bmClock();bmLastReport=0;bmState=@"waiting_for_first_sample";
    dispatch_source_set_timer(bmTimer,DISPATCH_TIME_NOW,5*NSEC_PER_MSEC,NSEC_PER_MSEC);bmWriteReport();
}
static void bmRefresh(void) {
    if(!bmReady())return;
    BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:BMEnableKey];int orientation=0;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive){
        UIWindowScene *ws=(UIWindowScene *)scene;orientation=(int)ws.effectiveGeometry.interfaceOrientation;break;
    }
    dispatch_async(bmQueue,^{bmConfigure(active,enabled,orientation);});
}
__attribute__((constructor)) static void bmInstall(void) {
    @autoreleasepool{
        [NSUserDefaults.standardUserDefaults registerDefaults:@{BMEnableKey:@YES}];
        // Keep the six-axis device advertised so the bridge can be toggled live.
        setenv("TOTK_GYRO","1",1);
        if(!bmReady())return;
        bmQueue=dispatch_queue_create("local.botw.ipad-motion",DISPATCH_QUEUE_SERIAL);
        bmReportQueue=dispatch_queue_create("local.botw.motion-report",DISPATCH_QUEUE_SERIAL);
        bmTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,bmQueue);
        dispatch_source_set_timer(bmTimer,DISPATCH_TIME_FOREVER,5*NSEC_PER_MSEC,NSEC_PER_MSEC);
        dispatch_source_set_event_handler(bmTimer,^{@autoreleasepool{bmTick();}});dispatch_resume(bmTimer);
        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){bmRefresh();}];
        [nc addObserverForName:BOTW_SETTINGS_CHANGED object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){bmRefresh();}];
        [nc addObserverForName:BOTW_MOTION_RECENTER object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
            dispatch_async(bmQueue,^{
                BOOL ok=bmOwned && bmRunning;
                if(ok)bmReset();
                bmWriteReport();
                dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:BOTW_MOTION_RECENTERED object:@(ok)];});
            });
        }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){dispatch_async(bmQueue,^{bmConfigure(NO,NO,0);});}];
        NSTimer *t=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *v){bmRefresh();}];
        [NSRunLoop.mainRunLoop addTimer:t forMode:NSRunLoopCommonModes];
    }
}

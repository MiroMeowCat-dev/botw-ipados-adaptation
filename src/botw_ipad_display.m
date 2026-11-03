// Local display preferences for the user's pinned BotW iOS build.
// No networking, account access, executable memory writes, or game-data edits.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#include <stdlib.h>
#include <string.h>
#include "botw_pacing_policy.h"
#include "botw_settings_shared.h"

static NSString *const ProfileKey = @"BOTW_IPAD_DISPLAY_PROFILE";
static NSString *const AspectKey = @"BOTW_IPAD_ASPECT";
static NSString *const RateKey = @"BOTW_IPAD_FRAME_CAP";
static NSString *const ProbeKey = @"BOTW_IPAD_LOCAL_DIAGNOSTICS";
static NSMutableDictionary *report;
static NSMutableArray *samples;
static CFAbsoluteTime began;
static double previousCPU, previousWall;
static BOOL haveCPU;

static BOOL member(NSString *value, NSArray<NSString *> *values) {
    return [value isKindOfClass:NSString.class] && [values containsObject:value];
}

static void apply_preferences(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d registerDefaults:@{ProfileKey:@"1080", AspectKey:@"16:9", RateKey:@"auto", ProbeKey:@NO,BOTW_PERFORMANCE_KEY:@NO}];
    if(![d boolForKey:@"BOTW_DAILY_UI_V1"]){
        // Retire test-session diagnostics once; retain graphics, saves and layout.
        [d setBool:NO forKey:ProbeKey];[d setBool:NO forKey:@"TOTK_DEBUG_LOG"];
        [d setBool:NO forKey:BOTW_PERFORMANCE_KEY];
        if(![d objectForKey:BOTW_MENU_MODE_KEY]){
            id previous=[d objectForKey:@"BOTW_MENU_COMPAT_ENABLED"];
            [d setObject:previous && ![previous boolValue]?@"fullscreen":@"auto" forKey:BOTW_MENU_MODE_KEY];
        }
        [d setBool:YES forKey:@"BOTW_DAILY_UI_V1"];
    }
    BOOL performance=[d boolForKey:BOTW_PERFORMANCE_KEY];
    setenv("TOTK_HUD",performance?"1":"0",1);
    setenv("MTL_HUD_ENABLED",performance?"1":"0",1);
    setenv("MTL_HUD_INSIGHTS_ENABLED","0",1);
    setenv("MTL_HUD_LOG_ENABLED","0",1);
    setenv("MTL_HUD_LOG_SHADER_ENABLED","0",1);
    NSString *p = [d stringForKey:ProfileKey];
    if (!member(p, @[@"legacy", @"1080", @"panel", @"panel-mfx"])) p = @"1080";
    NSString *aspect = [d stringForKey:AspectKey];
    if (!member(aspect, @[@"16:9", @"screen"])) aspect = @"16:9";
    NSString *rate = [d stringForKey:RateKey];
    if (!member(rate, @[@"auto", @"30", @"60"])) rate = @"auto";
    BOOL legacy = [p isEqualToString:@"legacy"];
    BOOL panel = [p hasPrefix:@"panel"];
    BOOL mfx = [p isEqualToString:@"panel-mfx"];
    // The pinned launcher is patched to use overwrite=0 for its handheld default.
    // The existing docked game-code patch already selects a 1920x1080 scene.
    setenv("TOTK_OPERATION_MODE", legacy ? "handheld" : "docked", 1);
    setenv("TOTK_IOS_DRAWABLE_H", panel ? "0" : legacy ? "720" : "1080", 1);
    // This build targets the user's confirmed 11-inch M5 in landscape fullscreen.
    // Empty means the host's PHONE auto mode, which deliberately rejects ratios
    // below (16/9)*1.01. An iPad's 2420/1668 must be requested explicitly so the
    // game's aspect-writer patch starts enabled and the presenter can fill it.
    const char *aspectValue = [aspect isEqualToString:@"screen"] ? "2420x1668" : "0";
    setenv("TOTK_ASPECT", aspectValue, 1);
    setenv("TOTK_MFX_UPSCALE", mfx ? "1" : "0", 1);
    setenv("TOTK_MFX_OUTPUT", mfx ? "1" : "0", 1);
    // Keep frame interpolation off in this first resolution experiment.
    // The pinned iOS presentation path has not been validated for generated frames.
    setenv("TOTK_MFX", "0", 1);
    BotWPacingPolicy pacing=botw_pacing_policy([rate isEqualToString:@"30"]?30:[rate isEqualToString:@"60"]?60:0);
    if(pacing.target_hz) {
        const char *hz=pacing.target_hz==30?"30":"60";
        setenv("TOTK_PHONE_FPS",hz,1);
        setenv("DM_PRESENT_HZ",hz,1);
        // In the pinned normal present_ticks path DISPLAY requests one target
        // tick. GAME would multiply it by the game's own interval (usually 2),
        // which made the old explicit 60 Hz strategy run at 30 fps even in menus.
        // Keep the host's movie/held-30 rules and real-time simulation untouched.
        setenv("DM_PRESENT_INTERVAL","display",1);
    } // auto preserves the original launcher's pacing, for a fair baseline.
    report = [@{@"schema":@1, @"build":@"ipad-display-v10",
        @"selected_profile":p, @"selected_aspect":aspect, @"frame_cap":rate,
        @"requested_aspect_value":@(aspectValue),
        @"pacing_target_hz":@(pacing.target_hz),@"pacing_interval_mode":pacing.display_interval?@"display":@"preserve",
        @"performance_display_requested":@(performance),@"metal_insights_requested":@NO,
        @"game_time_step_modified_by_display_module":@NO,
        @"target_device":@"iPad Pro 11-inch M5, landscape fullscreen",
        @"expected_scene":legacy ? @"960x540" : @"1920x1080",
        @"expected_canvas":legacy ? @"1280x720" : @"1920x1080",
        @"scene_size_is_configuration_expectation_not_gpu_measurement":@YES,
        @"metalfx_output_requested":@(mfx), @"frame_interpolation_enabled":@NO,
        @"networking":@NO, @"account_access":@NO,
        @"notes":@"Drawable is measured after launch. Scene/canvas are expectations to cross-check with runtime log/HUD; GPU timings and actual MetalFX dispatch require runtime evidence."} mutableCopy];
    samples = [NSMutableArray new];
    began = CFAbsoluteTimeGetCurrent();
}

static CAMetalLayer *find_metal(UIView *view, unsigned depth) {
    if (!view || depth > 12) return nil;
    if ([view.layer isKindOfClass:CAMetalLayer.class]) return (CAMetalLayer *)view.layer;
    for (UIView *child in view.subviews) {
        CAMetalLayer *layer = find_metal(child, depth + 1);
        if (layer) return layer;
    }
    return nil;
}

static void write_report(void) {
    if (!report || ![NSUserDefaults.standardUserDefaults boolForKey:ProbeKey]) return;
    NSMutableDictionary *s = [NSMutableDictionary new];
    s[@"seconds_since_launch"] = @(CFAbsoluteTimeGetCurrent() - began);
    s[@"thermal_state"] = @(NSProcessInfo.processInfo.thermalState);
    s[@"low_power_mode"] = @(NSProcessInfo.processInfo.lowPowerModeEnabled);
    s[@"active_processor_count"] = @(NSProcessInfo.processInfo.activeProcessorCount);
    struct task_vm_info vm = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) == KERN_SUCCESS)
        s[@"process_physical_footprint_bytes"] = @(vm.phys_footprint);
    // RUSAGE cpu time includes completed worker threads; 100% means one CPU core.
    struct task_thread_times_info tt = {0};
    count = TASK_THREAD_TIMES_INFO_COUNT;
    double cpu = 0;
    if (task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&tt, &count) == KERN_SUCCESS) {
        cpu = tt.user_time.seconds + tt.user_time.microseconds / 1e6 + tt.system_time.seconds + tt.system_time.microseconds / 1e6;
        struct task_basic_info_64 basic = {0};
        count = TASK_BASIC_INFO_64_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO_64, (task_info_t)&basic, &count) == KERN_SUCCESS)
            cpu += basic.user_time.seconds + basic.user_time.microseconds / 1e6 + basic.system_time.seconds + basic.system_time.microseconds / 1e6;
        double wall = CFAbsoluteTimeGetCurrent();
        if (haveCPU && wall > previousWall && cpu >= previousCPU)
            s[@"process_cpu_percent_one_core_is_100"] = @((cpu - previousCPU) * 100 / (wall - previousWall));
        previousCPU = cpu; previousWall = wall; haveCPU = YES;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        UIScreen *screen = ws.screen;
        s[@"screen_native_pixels"] = @[@(screen.nativeBounds.size.width), @(screen.nativeBounds.size.height)];
        s[@"screen_maximum_fps"] = @(screen.maximumFramesPerSecond);
        for (UIWindow *w in ws.windows) {
            CAMetalLayer *layer = find_metal(w, 0);
            if (!layer) continue;
            s[@"measured_drawable_pixels"] = @[@(layer.drawableSize.width), @(layer.drawableSize.height)];
            s[@"view_points"] = @[@(w.bounds.size.width), @(w.bounds.size.height)];
            id<MTLDevice> gpu = layer.device;
            if (gpu) {
                s[@"gpu_name"] = gpu.name;
                s[@"metal_device_allocated_bytes"] = @(gpu.currentAllocatedSize);
                s[@"metal4_family_supported"] = @([gpu supportsFamily:MTLGPUFamilyMetal4]);
                s[@"bc_texture_compression_supported"] = @(gpu.supportsBCTextureCompression);
                // Dynamic lookup keeps the shim compatible with the pinned SDK.
                for (NSString *name in @[@"MTLFXSpatialScalerDescriptor", @"MTLFXTemporalScalerDescriptor", @"MTLFXFrameInterpolatorDescriptor"]) {
                    Class c = NSClassFromString(name);
                    SEL sel = NSSelectorFromString(@"supportsMetal4FX:");
                    if (c && [c respondsToSelector:sel]) {
                        BOOL (*call)(id, SEL, id) = (void *)[c methodForSelector:sel];
                        s[[name stringByAppendingString:@"_supports_metal4"]] = @(call(c, sel, gpu));
                    }
                }
            }
            break;
        }
    }
    [samples addObject:s];
    report[@"samples"] = samples;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *folder = [paths.firstObject stringByAppendingPathComponent:@"Tuning"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[folder stringByAppendingPathComponent:@"display-profile-v1.json"] options:NSDataWritingAtomic error:nil];
}

__attribute__((constructor)) static void setup(void) {
    @autoreleasepool {
        apply_preferences();
        // One small local report at 2, 7, ... 57 seconds, then no more polling.
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            static BOOL started;
            if (started || ![NSUserDefaults.standardUserDefaults boolForKey:ProbeKey]) return;
            started = YES;
            for (unsigned i = 0; i < 12; i++)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2 + 5 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) write_report();
                });
        }];
    }
}

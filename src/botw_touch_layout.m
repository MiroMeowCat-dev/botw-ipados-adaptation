// An on-device layout editor for the user's pinned TOTKTouchPad implementation.
// Uses Objective-C method replacement; no executable-memory writes or networking.
// The original input backend remains responsible for publishing gamepad state.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <string.h>
#include "botw_touch_geometry.h"
#import "botw_touch_button.h"
#include "botw_settings_shared.h"

enum { ButtonCount = 16, LeftStick = 16, RightStick = 17 };
static const void *StateKey = &StateKey;
static NSString *const SavedKey = @"BOTW_TOUCH_LAYOUT_V1";
static NSString *const EnabledKey = @"BOTW_TOUCH_EDITOR_ENABLED";
static Ivar Points, LeftOrigins, RightOrigins, Concealed;
static void (*OldButtons)(id, SEL, TouchButton *);
static CGPoint (*OldRest)(id, SEL, BOOL);
static CGFloat (*OldRadius)(id, SEL);
static uint64_t (*OldButtonAt)(id, SEL, CGPoint);
static void (*OldDraw)(id, SEL, CGRect);
static void (*OldBegan)(id, SEL, NSSet *, UIEvent *);
static void (*OldMoved)(id, SEL, NSSet *, UIEvent *);
static void (*OldEnded)(id, SEL, NSSet *, UIEvent *);
static void (*OldCancelled)(id, SEL, NSSet *, UIEvent *);
static void (*OldSafeArea)(id, SEL);
static void (*OldLayout)(id, SEL);

@class BotWTouchEditor;
@class BotWTouchState;
@interface BotWSettingsPresenter : NSObject
+ (void)presentForState:(BotWTouchState *)state;
@end
static NSHashTable<BotWTouchState *> *allTouchStates;
@interface BotWTouchPadAccess : UIView
- (void)buttons:(TouchButton *)buttons;
- (CGPoint)restingStick:(BOOL)right;
- (CGFloat)stickRadius;
- (void)updateState;
@end
@interface BotWTouchState : NSObject
@property(nonatomic,weak) BotWTouchPadAccess *pad;
@property(nonatomic,strong) NSMutableDictionary *items;
@property(nonatomic,strong) NSDictionary *beforeEdit;
@property(nonatomic,strong) UIButton *entry;
@property(nonatomic,strong) BotWTouchEditor *editor;
@property(nonatomic,strong) NSHashTable *ignored;
@property(nonatomic) CGFloat opacity, stickScale;
@property(nonatomic) BOOL floating;
@property(nonatomic) BOOL settingsPresented, haveVisibility, previousVisibility;
- (void)load:(NSDictionary *)data;
- (NSDictionary *)serialized;
- (void)begin;
- (void)finish:(BOOL)save;
- (void)reset;
- (void)placeEntry;
- (void)openSettings;
- (void)refreshPreferences;
@end
@interface BotWTouchHandle : UIView
@property(nonatomic) NSInteger control;
@property(nonatomic,weak) BotWTouchEditor *editor;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic) CGPoint start;
@end
@interface BotWTouchEditor : UIView
@property(nonatomic,weak) BotWTouchState *state;
@property(nonatomic,strong) UIView *bar, *inspector;
@property(nonatomic,strong) UILabel *titleLabel, *sizeLabel, *opacityLabel;
@property(nonatomic,strong) UILabel *modeHint;
@property(nonatomic,strong) UISlider *sizeSlider, *opacitySlider;
@property(nonatomic,strong) UISegmentedControl *stickMode;
@property(nonatomic,strong) NSMutableArray<BotWTouchHandle *> *handles;
@property(nonatomic) NSInteger selected;
- (instancetype)initWithState:(BotWTouchState *)state;
- (void)select:(NSInteger)control;
- (void)refresh;
@end

static BotWTouchState *state(id pad) { return objc_getAssociatedObject(pad, StateKey); }
static BOOL enabled(void) { return [NSUserDefaults.standardUserDefaults boolForKey:EnabledKey]; }
static BOOL controlsVisible(void) { return [NSUserDefaults.standardUserDefaults boolForKey:BOTW_CONTROLS_VISIBLE_KEY]; }
static BOOL editing(id pad) { return state(pad).editor != nil; }
static CGRect area(UIView *pad) {
    CGRect a = UIEdgeInsetsInsetRect(pad.bounds, pad.safeAreaInsets);
    return a.size.width > 1 && a.size.height > 1 ? CGRectInset(a, 6, 6) : CGRectInset(pad.bounds, 6, 6);
}
static NSString *key(NSInteger control) { return [NSString stringWithFormat:@"%ld", (long)control]; }
static NSMapTable *map(id pad, Ivar ivar) {
    id obj = object_getIvar(pad, ivar);
    return [obj isKindOfClass:NSMapTable.class] ? obj : nil;
}
static double number(id value, double fallback) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) ? [value doubleValue] : fallback;
}
static void releaseTouches(BotWTouchPadAccess *pad) {
    [map(pad, Points) removeAllObjects];
    [map(pad, LeftOrigins) removeAllObjects];
    [map(pad, RightOrigins) removeAllObjects];
    [state(pad).ignored removeAllObjects];
    [pad updateState];
}
static CGPoint positioned(BotWTouchState *s, NSInteger control, CGPoint original, CGFloat radius) {
    CGRect a = area(s.pad);
    NSDictionary *saved = s.items[key(control)];
    double nx = saved ? number(saved[@"x"], .5) : botw_normalized(original.x, a.origin.x, a.size.width);
    double ny = saved ? number(saved[@"y"], .5) : botw_normalized(original.y, a.origin.y, a.size.height);
    return CGPointMake(botw_control_center(nx, a.origin.x, a.size.width, radius + 4),
                       botw_control_center(ny, a.origin.y, a.size.height, radius + 4));
}
static CGFloat buttonScale(BotWTouchState *s, NSInteger control) {
    return botw_clamp(number(s.items[key(control)][@"scale"], 1), .65, 1.8, 1);
}
static void readButtons(BotWTouchPadAccess *pad, TouchButton *b) {
    OldButtons(pad, @selector(buttons:), b);
    if (!enabled() || !state(pad)) return;
    BotWTouchState *s = state(pad);
    for (NSInteger i = 0; i < ButtonCount; i++) {
        b[i].size *= buttonScale(s, i);
        b[i].at = positioned(s, i, b[i].at, b[i].size * .5);
    }
}
static CGFloat radius(BotWTouchPadAccess *pad) {
    return OldRadius(pad, @selector(stickRadius)) * (enabled() && state(pad) ? state(pad).stickScale : 1);
}
static CGPoint resting(BotWTouchPadAccess *pad, BOOL right) {
    CGPoint p = OldRest(pad, @selector(restingStick:), right);
    return enabled() && state(pad) ? positioned(state(pad), right ? RightStick : LeftStick, p, radius(pad)) : p;
}
static uint64_t hit(BotWTouchPadAccess *pad, CGPoint p) {
    if(!controlsVisible() || state(pad).settingsPresented || editing(pad))return 0;
    if (!enabled() || !state(pad)) return OldButtonAt(pad, @selector(buttonAt:), p);
    if (editing(pad)) return 0;
    TouchButton b[ButtonCount] = {0}; readButtons(pad, b);
    uint64_t bits = 0;
    for (int i = 0; i < ButtonCount; i++)
        if (hypot(p.x - b[i].at.x, p.y - b[i].at.y) < MAX(24, b[i].size * .75)) bits |= b[i].bit;
    return bits;
}

@implementation BotWTouchState
- (void)dealloc { [_entry removeFromSuperview]; }
- (instancetype)init {
    if ((self = [super init])) {
        self.ignored = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
        [self load:[NSUserDefaults.standardUserDefaults dictionaryForKey:SavedKey]];
    }
    return self;
}
- (void)load:(NSDictionary *)data {
    if (![data isKindOfClass:NSDictionary.class] || number(data[@"schema"], 0) != 1) data = @{};
    self.items = [NSMutableDictionary new];
    NSDictionary *items = data[@"items"];
    if ([items isKindOfClass:NSDictionary.class]) {
        for (NSInteger i = 0; i <= RightStick; i++) {
            id item = items[key(i)];
            if (![item isKindOfClass:NSDictionary.class]) continue;
            self.items[key(i)] = @{@"x":@(botw_clamp(number(item[@"x"], .5), 0, 1, .5)),
                @"y":@(botw_clamp(number(item[@"y"], .5), 0, 1, .5)),
                @"scale":@(botw_clamp(number(item[@"scale"], 1), .65, 1.8, 1))};
        }
    }
    self.opacity = botw_clamp(number(data[@"opacity"], .45), .15, .95, .45);
    self.stickScale = botw_clamp(number(data[@"stickScale"], 1), .65, 1.5, 1);
    self.floating = number(data[@"floating"], 1) != 0;
}
- (NSDictionary *)serialized {
    return @{@"schema":@1, @"items":[self.items copy], @"opacity":@(self.opacity),
             @"stickScale":@(self.stickScale), @"floating":@(self.floating)};
}
- (void)placeEntry {
    self.entry.hidden = ![NSUserDefaults.standardUserDefaults boolForKey:BOTW_SETTINGS_ENTRY_KEY] || self.editor != nil || self.settingsPresented;
    UIView *container=self.pad.window?:self.pad;
    if(self.entry.superview!=container)[container addSubview:self.entry];
    CGRect a=UIEdgeInsetsInsetRect(container.bounds,container.safeAreaInsets);
    self.entry.frame=CGRectMake(CGRectGetMidX(a)-46,CGRectGetMaxY(a)-48,92,40);
    [container bringSubviewToFront:self.entry];
}
- (void)openSettings { [BotWSettingsPresenter presentForState:self]; }
- (void)refreshPreferences {
    BOOL visible=controlsVisible();
    if((self.haveVisibility && self.previousVisibility!=visible) || (!enabled() && self.editor)) {
        if(self.editor)[self finish:NO];
        releaseTouches(self.pad);
    }
    self.previousVisibility=visible;self.haveVisibility=YES;
    [self placeEntry];[self.pad setNeedsDisplay];
}
- (void)begin {
    if (self.editor || !enabled() || !controlsVisible()) return;
    self.beforeEdit = [self serialized];
    releaseTouches(self.pad);
    self.editor = [[BotWTouchEditor alloc] initWithState:self];
    [self.pad addSubview:self.editor];
    [self placeEntry];
    self.editor.alpha = 0;
    [UIView animateWithDuration:.18 animations:^{ self.editor.alpha = 1; }];
    [self.pad setNeedsDisplay];
}
- (void)finish:(BOOL)save {
    if (save) [NSUserDefaults.standardUserDefaults setObject:[self serialized] forKey:SavedKey];
    else [self load:self.beforeEdit];
    [self.editor removeFromSuperview]; self.editor = nil; self.beforeEdit = nil;
    releaseTouches(self.pad); [self placeEntry]; [self.pad setNeedsDisplay];
}
- (void)reset { [self load:@{}]; [self.editor refresh]; [self.pad setNeedsDisplay]; }
@end

static UIButton *actionButton(NSString *text, id target, SEL selector) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:text forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}
static void attach(BotWTouchPadAccess *pad) {
    if (state(pad)) return;
    BotWTouchState *s = [BotWTouchState new]; s.pad = pad;
    objc_setAssociatedObject(pad, StateKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [allTouchStates addObject:s];
    s.entry = actionButton(@"设置", s, @selector(openSettings));
    s.entry.backgroundColor = [UIColor colorWithWhite:.05 alpha:.68];
    s.entry.layer.cornerRadius = 20;
    s.entry.accessibilityLabel = @"塞尔达设置";
    [s refreshPreferences];
}

@implementation BotWTouchHandle
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.label = [UILabel new]; self.label.textAlignment = NSTextAlignmentCenter;
        self.label.textColor = UIColor.whiteColor; self.label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.label.userInteractionEnabled = NO; [self addSubview:self.label];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pick:)]];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.label.frame = self.bounds; self.layer.cornerRadius = self.bounds.size.width * .5; }
- (void)pick:(UITapGestureRecognizer *)g { (void)g; [self.editor select:self.control]; }
- (void)drag:(UIPanGestureRecognizer *)g {
    BotWTouchState *s = self.editor.state;
    if (g.state == UIGestureRecognizerStateBegan) { self.start = self.center; [self.editor select:self.control]; }
    CGPoint delta = [g translationInView:self.editor];
    CGPoint p = CGPointMake(self.start.x + delta.x, self.start.y + delta.y);
    // Keep dragged controls reachable below the editor toolbar. The inspector
    // can be hidden with the toolbar's Panel button to reach covered controls.
    CGFloat r=self.bounds.size.width*.5;
    if(CGRectIntersectsRect(CGRectMake(p.x-r,p.y-r,r*2,r*2),self.editor.bar.frame))
        p.y=CGRectGetMaxY(self.editor.bar.frame)+r+4;
    CGRect a = area(s.pad);
    NSMutableDictionary *value = [s.items[key(self.control)] mutableCopy] ?: [NSMutableDictionary new];
    value[@"x"] = @(botw_normalized(p.x, a.origin.x, a.size.width));
    value[@"y"] = @(botw_normalized(p.y, a.origin.y, a.size.height));
    if (!value[@"scale"]) value[@"scale"] = @1;
    s.items[key(self.control)] = value;
    [self.editor refresh]; [s.pad setNeedsDisplay];
}
@end

@implementation BotWTouchEditor
- (instancetype)initWithState:(BotWTouchState *)s {
    if ((self = [super initWithFrame:s.pad.bounds])) {
        self.state = s; self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:.58];
        self.bar = [UIView new]; self.bar.backgroundColor = [UIColor colorWithWhite:.10 alpha:.98]; self.bar.layer.cornerRadius = 18;
        [self addSubview:self.bar];
        NSArray *titles = @[@"取消", @"恢复默认", @"面板", @"保存"];
        SEL selectors[] = {@selector(cancel), @selector(reset), @selector(togglePanel), @selector(save)};
        for (NSInteger i = 0; i < 4; i++) {
            UIButton *b = actionButton(titles[i], self, selectors[i]); b.tag = i;
            [self.bar addSubview:b];
        }
        self.inspector = [UIView new]; self.inspector.backgroundColor = [UIColor colorWithWhite:.10 alpha:.98];
        self.inspector.layer.cornerRadius = 18; [self addSubview:self.inspector];
        self.titleLabel = [UILabel new]; self.titleLabel.textColor = UIColor.whiteColor;
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [self.inspector addSubview:self.titleLabel];
        self.sizeLabel = [UILabel new]; self.opacityLabel = [UILabel new];
        for (UILabel *l in @[self.sizeLabel,self.opacityLabel]) {
            l.textColor = [UIColor colorWithWhite:.8 alpha:1]; l.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
            [self.inspector addSubview:l];
        }
        self.sizeSlider = [UISlider new]; self.opacitySlider = [UISlider new];
        self.sizeSlider.minimumValue = .65; self.sizeSlider.maximumValue = 1.8;
        self.opacitySlider.minimumValue = .15; self.opacitySlider.maximumValue = .95;
        for (UISlider *slider in @[self.sizeSlider,self.opacitySlider]) {
            slider.tintColor = [UIColor colorWithRed:.35 green:.88 blue:.77 alpha:1];
            [slider addTarget:self action:@selector(slider:) forControlEvents:UIControlEventValueChanged];
            [self.inspector addSubview:slider];
        }
        self.sizeSlider.accessibilityLabel = @"选中按钮大小"; self.opacitySlider.accessibilityLabel = @"全部按键透明度";
        self.stickMode = [[UISegmentedControl alloc] initWithItems:@[@"浮动摇杆",@"固定摇杆"]];
        self.stickMode.selectedSegmentTintColor = [UIColor colorWithWhite:.3 alpha:1];
        [self.stickMode setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateNormal];
        [self.stickMode setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateSelected];
        [self.stickMode addTarget:self action:@selector(mode:) forControlEvents:UIControlEventValueChanged];
        [self.inspector addSubview:self.stickMode];
        self.modeHint=[UILabel new];self.modeHint.textColor=[UIColor colorWithWhite:.7 alpha:1];
        self.modeHint.font=[UIFont systemFontOfSize:11];[self.inspector addSubview:self.modeHint];
        self.handles = [NSMutableArray new]; self.selected = -1;
        for (NSInteger i = 0; i <= RightStick; i++) {
            BotWTouchHandle *h = [[BotWTouchHandle alloc] initWithFrame:CGRectZero]; h.control = i; h.editor = self;
            h.layer.borderWidth = 1.5; [self addSubview:h]; [self.handles addObject:h];
        }
        [self bringSubviewToFront:self.inspector]; [self bringSubviewToFront:self.bar];
        [self refresh];
    }
    return self;
}
- (void)cancel { [self.state finish:NO]; }
- (void)save { [self.state finish:YES]; }
- (void)reset { [self.state reset]; }
- (void)togglePanel { self.inspector.hidden=!self.inspector.hidden; }
- (void)select:(NSInteger)control { self.selected = control; [self refresh]; }
- (void)mode:(UISegmentedControl *)v { self.state.floating = v.selectedSegmentIndex == 0;[self refresh]; }
- (void)slider:(UISlider *)slider {
    BotWTouchState *s = self.state;
    if (slider == self.opacitySlider) s.opacity = slider.value;
    else if (self.selected >= LeftStick) s.stickScale = MIN(slider.value, 1.5);
    else if (self.selected >= 0) {
        NSMutableDictionary *v = [s.items[key(self.selected)] mutableCopy] ?: [NSMutableDictionary new];
        TouchButton b[ButtonCount] = {0}; readButtons(s.pad,b); CGRect a = area(s.pad);
        if (!v[@"x"]) v[@"x"] = @(botw_normalized(b[self.selected].at.x,a.origin.x,a.size.width));
        if (!v[@"y"]) v[@"y"] = @(botw_normalized(b[self.selected].at.y,a.origin.y,a.size.height));
        v[@"scale"] = @(slider.value); s.items[key(self.selected)] = v;
    }
    [self refresh]; [s.pad setNeedsDisplay];
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGRect a = area(self.state.pad);
    CGFloat bw = MIN(420,a.size.width - 24);
    self.bar.frame = CGRectMake(CGRectGetMidX(a)-bw/2,CGRectGetMinY(a)+10,bw,48);
    for (UIButton *b in self.bar.subviews) b.frame = CGRectMake(b.tag*bw/4,4,bw/4,40);
    CGFloat iw = MIN(300,a.size.width - 24);
    self.inspector.frame = CGRectMake(CGRectGetMidX(a)-iw/2,CGRectGetMaxY(a)-234,iw,224);
    self.titleLabel.frame = CGRectMake(16,12,iw-32,22);
    self.sizeLabel.frame = CGRectMake(16,42,iw-32,17); self.sizeSlider.frame = CGRectMake(16,60,iw-32,28);
    self.opacityLabel.frame = CGRectMake(16,94,iw-32,17); self.opacitySlider.frame = CGRectMake(16,112,iw-32,28);
    self.stickMode.frame = CGRectMake(16,156,iw-32,32);
    self.modeHint.frame=CGRectMake(16,196,iw-32,16);
    [self refresh];
}
- (void)refresh {
    BotWTouchState *s = self.state; if (!s.pad) return;
    TouchButton b[ButtonCount] = {0}; readButtons(s.pad,b);
    for (NSInteger i = 0; i <= RightStick; i++) {
        BotWTouchHandle *h = self.handles[i]; BOOL selected = i == self.selected;
        CGPoint p = i < ButtonCount ? b[i].at : resting(s.pad,i == RightStick);
        CGFloat size = i < ButtonCount ? b[i].size : radius(s.pad)*2;
        h.bounds = CGRectMake(0,0,size,size); h.center = p;
        h.label.text = i < ButtonCount ? b[i].label : i == LeftStick ? @"移动" : @"视角";
        h.label.font = [UIFont systemFontOfSize:i<ButtonCount?MAX(12,MIN(22,size*.32)):15 weight:UIFontWeightSemibold];
        h.alpha = selected ? 1 : MAX(.25,s.opacity);
        h.accessibilityLabel = [@"拖动 " stringByAppendingString:h.label.text];
        h.backgroundColor = selected ? [UIColor colorWithRed:.10 green:.42 blue:.36 alpha:.9] : [UIColor colorWithWhite:.18 alpha:.8];
        h.layer.borderColor = selected ? [UIColor colorWithRed:.35 green:.88 blue:.77 alpha:1].CGColor : [UIColor colorWithWhite:1 alpha:.6].CGColor;
    }
    BOOL stick = self.selected >= LeftStick;
    NSString *name = self.selected < 0 ? @"拖动控件，点选后调整大小" : stick ? @"双摇杆大小 · 位置分别拖动" : [@"选中：" stringByAppendingString:b[self.selected].label];
    self.titleLabel.text = name;
    self.sizeSlider.enabled = self.selected >= 0;
    self.sizeSlider.maximumValue = stick ? 1.5 : 1.8;
    self.sizeSlider.value = stick ? s.stickScale : self.selected >= 0 ? buttonScale(s,self.selected) : 1;
    self.opacitySlider.value = s.opacity;
    self.sizeLabel.text = [NSString stringWithFormat:@"大小  %.0f%%",self.sizeSlider.value*100];
    self.opacityLabel.text = [NSString stringWithFormat:@"全部按键不透明度  %.0f%%",s.opacity*100];
    self.stickMode.selectedSegmentIndex = s.floating ? 0 : 1;
    self.modeHint.text=s.floating?@"浮动：摇杆跟随手指按下的位置":@"固定：在放置的摇杆区域内操作";
    [self setNeedsDisplay];
}
@end

static void drawStick(CGContextRef c, CGPoint center, CGPoint finger, CGFloat r, UIColor *ink) {
    CGContextSetStrokeColorWithColor(c, ink.CGColor); CGContextSetLineWidth(c,1.5);
    CGContextStrokeEllipseInRect(c,CGRectMake(center.x-r,center.y-r,r*2,r*2));
    CGFloat dx=finger.x-center.x,dy=finger.y-center.y,d=hypot(dx,dy);
    if (d>r) {dx*=r/d;dy*=r/d;}
    CGFloat knob=MIN(46,r*.75);
    CGContextSetFillColorWithColor(c,[UIColor colorWithWhite:.15 alpha:.5].CGColor);
    CGRect box=CGRectMake(center.x+dx-knob/2,center.y+dy-knob/2,knob,knob);
    CGContextFillEllipseInRect(c,box); CGContextStrokeEllipseInRect(c,box);
}
static void drawPad(BotWTouchPadAccess *pad, SEL sel, CGRect rect) {
    if(!controlsVisible() || state(pad).settingsPresented)return;
    if (!enabled() || !state(pad)) {OldDraw(pad,sel,rect);return;}
    BotWTouchState *s=state(pad);
    BOOL concealed=*(const BOOL *)((const char *)(__bridge void *)pad+ivar_getOffset(Concealed));
    if (concealed || s.editor) return;
    CGContextRef c=UIGraphicsGetCurrentContext(); if (!c) return;
    CGContextSaveGState(c); CGContextSetAlpha(c,s.opacity);
    UIColor *ink=UIColor.whiteColor; NSMapTable *points=map(pad,Points),*left=map(pad,LeftOrigins),*right=map(pad,RightOrigins);
    if (!left.count) {CGPoint p=resting(pad,NO);drawStick(c,p,p,radius(pad),ink);}
    if (!right.count) {CGPoint p=resting(pad,YES);drawStick(c,p,p,radius(pad),ink);}
    for (NSMapTable *origins in @[left,right]) for (UITouch *t in origins.keyEnumerator)
        drawStick(c,[[origins objectForKey:t] CGPointValue],[[points objectForKey:t] CGPointValue],radius(pad),ink);
    TouchButton b[ButtonCount] = {0};readButtons(pad,b);
    uint64_t pressedBits=0;
    for (UITouch *t in points.keyEnumerator) if (![left objectForKey:t] && ![right objectForKey:t])
        pressedBits|=hit(pad,[[points objectForKey:t] CGPointValue]);
    for (int i=0;i<ButtonCount;i++) {
        BOOL pressed=(pressedBits&b[i].bit)!=0;
        CGRect box=CGRectMake(b[i].at.x-b[i].size/2,b[i].at.y-b[i].size/2,b[i].size,b[i].size);
        CGContextSetFillColorWithColor(c,[UIColor colorWithWhite:pressed?.65:.08 alpha:pressed?.8:.36].CGColor);
        CGContextFillEllipseInRect(c,box);CGContextSetStrokeColorWithColor(c,ink.CGColor);CGContextSetLineWidth(c,1.5);CGContextStrokeEllipseInRect(c,box);
        NSDictionary *attrs=@{NSFontAttributeName:[UIFont systemFontOfSize:MAX(12,MIN(22,b[i].size*.32)) weight:UIFontWeightSemibold],NSForegroundColorAttributeName:ink};
        CGSize z=[b[i].label sizeWithAttributes:attrs];[b[i].label drawAtPoint:CGPointMake(b[i].at.x-z.width/2,b[i].at.y-z.height/2) withAttributes:attrs];
    }
    CGContextRestoreGState(c);
}
static void began(BotWTouchPadAccess *pad,SEL sel,NSSet *touches,UIEvent *event) {
    if(!controlsVisible() || state(pad).settingsPresented)return;
    if (!enabled() || !state(pad)) {OldBegan(pad,sel,touches,event);return;}
    BotWTouchState *s=state(pad); if (s.editor) return;
    if (s.floating) {OldBegan(pad,sel,touches,event);return;}
    NSMutableSet *accepted=[NSMutableSet new];
    CGPoint l=resting(pad,NO),r=resting(pad,YES);CGFloat reach=radius(pad)*1.6;
    for (UITouch *t in touches) {
        CGPoint p=[t locationInView:pad];
        if (hit(pad,p) || hypot(p.x-l.x,p.y-l.y)<=reach || hypot(p.x-r.x,p.y-r.y)<=reach) [accepted addObject:t];
        else [s.ignored addObject:t];
    }
    OldBegan(pad,sel,accepted,event);
    for (UITouch *t in accepted) {
        CGPoint p=[t locationInView:pad]; if (hit(pad,p)) continue;
        [map(pad,LeftOrigins) removeObjectForKey:t];[map(pad,RightOrigins) removeObjectForKey:t];
        BOOL right=hypot(p.x-r.x,p.y-r.y)<hypot(p.x-l.x,p.y-l.y);
        [map(pad,right?RightOrigins:LeftOrigins) setObject:[NSValue valueWithCGPoint:right?r:l] forKey:t];
    }
    [pad updateState];
}
static void moved(BotWTouchPadAccess *pad,SEL sel,NSSet *touches,UIEvent *event) {
    if(!controlsVisible() || state(pad).settingsPresented)return;
    if (enabled() && editing(pad)) return;
    if (enabled() && state(pad)) {
        NSMutableSet *accepted=[NSMutableSet new];
        for(id t in touches) if([map(pad,Points) objectForKey:t] && ![state(pad).ignored containsObject:t]) [accepted addObject:t];
        OldMoved(pad,sel,accepted,event);
    } else OldMoved(pad,sel,touches,event);
}
static void ended(BotWTouchPadAccess *pad,SEL sel,NSSet *touches,UIEvent *event) {
    if(!controlsVisible() || state(pad).settingsPresented)return;
    if (enabled() && editing(pad)) return;
    for (id t in touches) [state(pad).ignored removeObject:t];
    OldEnded(pad,sel,touches,event);
}
static void cancelled(BotWTouchPadAccess *pad,SEL sel,NSSet *touches,UIEvent *event) {
    if(!controlsVisible() || state(pad).settingsPresented)return;
    if (enabled() && editing(pad)) return;
    for (id t in touches) [state(pad).ignored removeObject:t];
    OldCancelled(pad,sel,touches,event);
}
static void safeArea(BotWTouchPadAccess *pad,SEL sel) {OldSafeArea(pad,sel);[state(pad) placeEntry];}
static void layoutPad(BotWTouchPadAccess *pad,SEL sel) {OldLayout(pad,sel);attach(pad);[state(pad) placeEntry];[state(pad).editor setNeedsLayout];}
// Objective-C IMPs always include the implicit selector argument. Keep wrappers
// separate from the typed helpers used by the editor to preserve the ARM64 ABI.
static void hookedButtons(BotWTouchPadAccess *pad,SEL sel,TouchButton *b) {(void)sel;readButtons(pad,b);}
static CGPoint hookedRest(BotWTouchPadAccess *pad,SEL sel,BOOL right) {(void)sel;return resting(pad,right);}
static CGFloat hookedRadius(BotWTouchPadAccess *pad,SEL sel) {(void)sel;return radius(pad);}
static uint64_t hookedHit(BotWTouchPadAccess *pad,SEL sel,CGPoint p) {(void)sel;return hit(pad,p);}
static void *replace(Class cls,const char *name,IMP impl) {
    return (void *)method_setImplementation(class_getInstanceMethod(cls,sel_registerName(name)),impl);
}
__attribute__((constructor)) static void install(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{EnabledKey:@YES,BOTW_CONTROLS_VISIBLE_KEY:@YES,BOTW_SETTINGS_ENTRY_KEY:@YES}];
        allTouchStates=[NSHashTable weakObjectsHashTable];
        Class cls=objc_getClass("TOTKTouchPad"); if(!cls)return;
        Points=class_getInstanceVariable(cls,"points");LeftOrigins=class_getInstanceVariable(cls,"leftOrigins");
        RightOrigins=class_getInstanceVariable(cls,"rightOrigins");Concealed=class_getInstanceVariable(cls,"concealed");
        if(!Points||!LeftOrigins||!RightOrigins||!Concealed)return;
        const char *type=ivar_getTypeEncoding(Concealed);if(!type || (strcmp(type,"B")&&strcmp(type,"c")))return;
        const char *methods[]={"initWithFrame:","buttons:","restingStick:","stickRadius","buttonAt:","drawRect:","touchesBegan:withEvent:","touchesMoved:withEvent:","touchesEnded:withEvent:","touchesCancelled:withEvent:","safeAreaInsetsDidChange","updateState"};
        const unsigned counts[]={3,3,3,2,3,3,4,4,4,4,2,2};
        for(unsigned i=0;i<sizeof(methods)/sizeof(methods[0]);i++) {
            Method m=class_getInstanceMethod(cls,sel_registerName(methods[i]));
            if(!m || method_getNumberOfArguments(m)!=counts[i])return;
        }
        // Attach lazily during layout; leave initWithFrame: ownership untouched.
        OldButtons=replace(cls,"buttons:",(IMP)hookedButtons);
        OldRest=replace(cls,"restingStick:",(IMP)hookedRest);OldRadius=replace(cls,"stickRadius",(IMP)hookedRadius);
        OldButtonAt=replace(cls,"buttonAt:",(IMP)hookedHit);OldDraw=replace(cls,"drawRect:",(IMP)drawPad);
        OldBegan=replace(cls,"touchesBegan:withEvent:",(IMP)began);OldMoved=replace(cls,"touchesMoved:withEvent:",(IMP)moved);
        OldEnded=replace(cls,"touchesEnded:withEvent:",(IMP)ended);OldCancelled=replace(cls,"touchesCancelled:withEvent:",(IMP)cancelled);
        OldSafeArea=replace(cls,"safeAreaInsetsDidChange",(IMP)safeArea);
        Method layout=class_getInstanceMethod(cls,@selector(layoutSubviews));
        OldLayout=(void *)method_getImplementation(layout);
        if(!class_addMethod(cls,@selector(layoutSubviews),(IMP)layoutPad,method_getTypeEncoding(layout)))
            OldLayout=replace(cls,"layoutSubviews",(IMP)layoutPad);
        for(NSString *name in @[BOTW_SETTINGS_CHANGED,UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
                for(BotWTouchState *s in allTouchStates.allObjects)[s refreshPreferences];
            }];
    }
}

#include "botw_ingame_settings.m"

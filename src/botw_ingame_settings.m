// Included by the touch module: one native settings sheet, no game data access.
@interface BotWSettingsChoices : UITableViewController
@property(nonatomic,strong) NSDictionary *row;
@property(nonatomic,copy) void (^changed)(void);
@end

@interface BotWGameSettings : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) BotWTouchState *touchState;
@property(nonatomic,strong) NSArray<NSDictionary *> *groups;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic) BOOL needsRelaunch, finished, calibrating;
- (void)finishSettings;
@end

static BOOL settingsRowEnabled(NSDictionary *row) {
    for(NSString *required in row[@"requires"])
        if(![NSUserDefaults.standardUserDefaults boolForKey:required])return NO;
    return YES;
}
static NSString *settingsChoiceTitle(NSDictionary *row) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:row[@"key"]]?:row[@"default"];
    NSUInteger index=[row[@"values"] indexOfObject:value];
    return index<[row[@"titles"] count]?row[@"titles"][index]:@"默认";
}
static void settingsNotify(void) {
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:BOTW_SETTINGS_CHANGED object:nil];
}

@implementation BotWSettingsChoices
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad];self.title=self.row[@"title"]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;(void)section;return [self.row[@"values"] count];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"choice"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"choice"];
    cell.textLabel.text=self.row[@"titles"][path.row];cell.textLabel.numberOfLines=2;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    id value=[NSUserDefaults.standardUserDefaults objectForKey:self.row[@"key"]]?:self.row[@"default"];
    BOOL selected=[value isEqual:self.row[@"values"][path.row]];
    cell.accessoryType=selected?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    cell.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    (void)table;NSString *key=self.row[@"key"];id value=self.row[@"values"][path.row];
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    if([key isEqualToString:BOTW_MENU_MODE_KEY])
        [NSUserDefaults.standardUserDefaults setBool:[value isEqual:@"auto"] forKey:@"BOTW_MENU_COMPAT_ENABLED"];
    settingsNotify();if(self.changed)self.changed();
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@implementation BotWGameSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"塞尔达设置";
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=52;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    NSData *data=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"BotWSettings" withExtension:@"json"]];
    NSDictionary *document=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    self.groups=[document[@"groups"] isKindOfClass:NSArray.class]?document[@"groups"]:@[];
    NSMutableDictionary *defaults=[NSMutableDictionary new];
    for(NSDictionary *group in self.groups)for(NSDictionary *row in group[@"rows"])
        if(row[@"key"] && row[@"default"])defaults[row[@"key"]]=row[@"default"];
    [NSUserDefaults.standardUserDefaults registerDefaults:defaults];
    self.hint=[UILabel new];self.hint.numberOfLines=0;
    self.hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];self.hint.textColor=UIColor.secondaryLabelColor;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(calibrationFinished:) name:BOTW_MOTION_RECENTERED object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadPreferences:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self updateHint];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)reloadPreferences:(NSNotification *)notification {(void)notification;[self.tableView reloadData];[self updateHint];}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];[self updateHint];}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self updateHint];}
- (void)updateHint {
    self.hint.text=self.needsRelaunch?@"设置已保存。画面、语言和性能显示的更改，下次启动游戏生效。":@"建议先在游戏内暂停，再调整设置。";
    CGFloat width=MAX(240,self.tableView.bounds.size.width-48);
    CGSize fit=[self.hint sizeThatFits:CGSizeMake(width,CGFLOAT_MAX)];
    UIView *header=self.tableView.tableHeaderView;
    if(!header){header=[UIView new];[header addSubview:self.hint];}
    CGFloat height=MAX(48,fit.height+28);
    self.hint.frame=CGRectMake(24,14,width,fit.height);
    if(fabs(header.frame.size.height-height)>.5 || !self.tableView.tableHeaderView){
        header.frame=CGRectMake(0,0,self.tableView.bounds.size.width,height);self.tableView.tableHeaderView=header;
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {(void)table;return self.groups.count;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {(void)table;return [self.groups[section][@"rows"] count];}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {(void)table;return self.groups[section][@"title"];}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {(void)table;return self.groups[section][@"footer"];}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *row=self.groups[path.section][@"rows"][path.row];
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"setting"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"setting"];
    cell.textLabel.text=row[@"title"];cell.textLabel.numberOfLines=2;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.numberOfLines=2;cell.detailTextLabel.text=nil;
    cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone;
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    BOOL active=settingsRowEnabled(row);cell.userInteractionEnabled=active;
    cell.textLabel.textColor=active?UIColor.labelColor:UIColor.tertiaryLabelColor;
    NSString *type=row[@"type"];
    if([type isEqual:@"toggle"]){
        UISwitch *control=[UISwitch new];control.on=[NSUserDefaults.standardUserDefaults boolForKey:row[@"key"]];
        control.accessibilityLabel=row[@"title"];control.enabled=active;
        objc_setAssociatedObject(control,@selector(toggleSetting:),row,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=control;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if([type isEqual:@"choice"]){
        cell.detailTextLabel.text=settingsChoiceTitle(row);cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if([type isEqual:@"info"]){
        cell.detailTextLabel.text=row[@"detail"];cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.userInteractionEnabled=NO;
    } else if(active){cell.textLabel.textColor=self.view.tintColor;}
    return cell;
}
- (void)toggleSetting:(UISwitch *)control {
    NSDictionary *row=objc_getAssociatedObject(control,@selector(toggleSetting:));
    [NSUserDefaults.standardUserDefaults setBool:control.on forKey:row[@"key"]];
    if([row[@"restart"] boolValue])self.needsRelaunch=YES;
    settingsNotify();[self.tableView reloadData];[self updateHint];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSDictionary *row=self.groups[path.section][@"rows"][path.row];if(!settingsRowEnabled(row))return;
    if([row[@"type"] isEqual:@"choice"]){
        BotWSettingsChoices *choices=[BotWSettingsChoices new];choices.row=row;
        __weak BotWGameSettings *weakSelf=self;
        choices.changed=^{if([row[@"restart"] boolValue])weakSelf.needsRelaunch=YES;};
        [self.navigationController pushViewController:choices animated:YES];return;
    }
    NSString *action=row[@"action"];
    if([action isEqual:@"layout"]){
        BotWTouchState *s=self.touchState;
        [self dismissViewControllerAnimated:YES completion:^{[self finishSettings];[s begin];}];
    } else if([action isEqual:@"recenter"] && !self.calibrating){
        self.calibrating=YES;[NSNotificationCenter.defaultCenter postNotificationName:BOTW_MOTION_RECENTER object:nil];
        __weak BotWGameSettings *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(weakSelf.calibrating)[weakSelf calibrationFinished:[NSNotification notificationWithName:BOTW_MOTION_RECENTERED object:@NO]];
        });
    } else if([action isEqual:@"system"]){
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }
}
- (void)calibrationFinished:(NSNotification *)notification {
    if(!self.calibrating)return;self.calibrating=NO;
    if(!self.view.window || self.presentedViewController)return;
    BOOL success=[notification.object boolValue];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:success?@"已重新校准":@"体感暂未就绪" message:success?@"现在可以继续体感瞄准。":@"请保持横屏，确认已开启iPad体感后稍后再试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)finishSettings {
    if(self.finished)return;self.finished=YES;
    self.touchState.settingsPresented=NO;releaseTouches(self.touchState.pad);
    [self.touchState refreshPreferences];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:^{[self finishSettings];}]; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {(void)presentationController;[self finishSettings];}
@end

@implementation BotWSettingsPresenter
+ (void)presentForState:(BotWTouchState *)s {
    if(!s.pad.window || s.editor || s.settingsPresented)return;
    UIViewController *host=s.pad.window.rootViewController;
    while(host.presentedViewController)host=host.presentedViewController;
    if(!host || host.isBeingDismissed || host.isBeingPresented)return;
    releaseTouches(s.pad);s.settingsPresented=YES;[s placeEntry];[s.pad setNeedsDisplay];
    BotWGameSettings *settings=[BotWGameSettings new];settings.touchState=s;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle=UIModalPresentationFormSheet;nav.preferredContentSize=CGSizeMake(580,680);
    [host presentViewController:nav animated:YES completion:^{nav.presentationController.delegate=settings;}];
}
@end

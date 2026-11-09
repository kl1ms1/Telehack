#import "THPanel.h"
#import "THFeatures.h"
#import "THSettings.h"
#import "THNetFilter.h"
#import "THLog.h"
#import <objc/runtime.h>

static const NSTimeInterval kReadUnlockSeconds = 30;
static char kGestureKey;

#pragma mark - Presenting

@interface THPanelPresenter : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end

@implementation THPanelPresenter

+ (instancetype)shared {
    static THPanelPresenter *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [self new]; });
    return p;
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window || objc_getAssociatedObject(window, &kGestureKey)) return;
    UILongPressGestureRecognizer *g =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handle:)];
    g.numberOfTouchesRequired = 3;
    g.minimumPressDuration = 0.6;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delegate = self;
    [window addGestureRecognizer:g];
    objc_setAssociatedObject(window, &kGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)attachToAllWindows {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [self attachToWindow:w];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)handle:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self presentFromWindow:g.view.window ?: (UIWindow *)g.view];
}

- (void)presentFromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    if ([top isKindOfClass:[UINavigationController class]] &&
        [((UINavigationController *)top).viewControllers.firstObject isKindOfClass:[THPanelViewController class]])
        return;

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:[THPanelViewController new]];
    [top presentViewController:nav animated:YES completion:nil];
}

- (void)showFirstRunHint {
    NSString *key = @"telehack.hintShown";
    if ([[NSUserDefaults standardUserDefaults] boolForKey:key]) return;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) window = w;
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"TeleHack загружен"
                         message:@"Зажмите экран тремя пальцами, чтобы открыть настройки плагинов."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Открыть" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *_) { [self presentFromWindow:window]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Понятно" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

@end

void THPanelPresentFrom(UIViewController *presenter) {
    if (!presenter) return;
    UIViewController *top = presenter;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]] &&
        [((UINavigationController *)top).viewControllers.firstObject isKindOfClass:[THPanelViewController class]])
        return;
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:[THPanelViewController new]];
    [top presentViewController:nav animated:YES completion:nil];
}

void THPanelInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        THPanelPresenter *p = [THPanelPresenter shared];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        void (^attach)(NSNotification *) = ^(NSNotification *n) {
            if ([n.object isKindOfClass:[UIWindow class]]) [p attachToWindow:n.object];
            [p attachToAllWindows];
        };
        [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:attach];
        [nc addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:nil usingBlock:attach];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:attach];
        [p attachToAllWindows];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [p attachToAllWindows];
            [p showFirstRunHint];
        });
    });
}

#pragma mark - Panel

typedef NS_ENUM(NSInteger, THRow) {
    THRowStatus, THRowGhostMaster, THRowReadNow,
    THRowCustomRules, THRowLogSwitch, THRowLogOpen, THRowAbout,
};

@interface THPanelSection : NSObject
@property (nonatomic, copy) NSString *header;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, strong) NSMutableArray *rows; // NSNumber(THRow) or THFeature
@end
@implementation THPanelSection
@end

@implementation THPanelViewController {
    NSArray<THPanelSection *> *_sections;
    NSTimer *_timer;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TeleHack";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(close)];
    [self buildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    __block BOOL wasUnlocked = NO;
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) {
        BOOL unlocked = [THSettings shared].readUnlockRemaining > 0;
        if (unlocked || wasUnlocked) [weakSelf reloadReadNowRow];
        wasUnlocked = unlocked;
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)reloadReadNowRow {
    [_sections enumerateObjectsUsingBlock:^(THPanelSection *sec, NSUInteger si, BOOL *stop) {
        NSUInteger ri = [sec.rows indexOfObject:@(THRowReadNow)];
        if (ri != NSNotFound) {
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)ri inSection:(NSInteger)si]]
                                  withRowAnimation:UITableViewRowAnimationNone];
            *stop = YES;
        }
    }];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)buildSections {
    NSMutableArray *s = [NSMutableArray array];
    THPanelSection *(^add)(NSString *, NSString *) = ^(NSString *h, NSString *f) {
        THPanelSection *sec = [THPanelSection new];
        sec.header = h; sec.footer = f; sec.rows = [NSMutableArray array];
        [s addObject:sec];
        return sec;
    };

    [add(nil, nil).rows addObject:@(THRowStatus)];

    THPanelSection *ghost = add(@"Режим призрака",
        @"Заблокированные запросы не уходят на сервер. После выключения уже открытые чаты могут "
        @"отметиться прочитанными только после перезапуска Telegram.");
    [ghost.rows addObject:@(THRowGhostMaster)];
    [ghost.rows addObjectsFromArray:[THFeatures inSection:THSectionGhost]];
    [ghost.rows addObject:@(THRowReadNow)];

    THPanelSection *privacy = add(@"Приватность", nil);
    [privacy.rows addObjectsFromArray:[THFeatures inSection:THSectionPrivacy]];

    THPanelSection *ads = add(@"Реклама", nil);
    [ads.rows addObjectsFromArray:[THFeatures inSection:THSectionAds]];

    THPanelSection *custom = add(@"Свои правила",
        @"Блокировка любых MTProto-методов по constructor ID (hex). ID можно найти в журнале запросов.");
    [custom.rows addObject:@(THRowCustomRules)];

    THPanelSection *debug = add(@"Отладка", nil);
    [debug.rows addObject:@(THRowLogSwitch)];
    [debug.rows addObject:@(THRowLogOpen)];

    [add(nil, nil).rows addObject:@(THRowAbout)];
    _sections = s;
}

- (BOOL)ghostAllOn {
    for (THFeature *f in [THFeatures inSection:THSectionGhost])
        if (![[THSettings shared] boolForKey:f.key]) return NO;
    return YES;
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s].header; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return _sections[s].footer; }

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag action:(SEL)action {
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 0;
    THSettings *st = [THSettings shared];
    id row = _sections[ip.section].rows[ip.row];

    if ([row isKindOfClass:[THFeature class]]) {
        THFeature *f = row;
        NSUInteger idx = [[THFeatures all] indexOfObject:f];
        cell.textLabel.text = f.title;
        cell.detailTextLabel.text = f.subtitle;
        cell.accessoryView = [self switchOn:[st boolForKey:f.key] tag:(NSInteger)idx action:@selector(featureToggled:)];
        return cell;
    }

    switch ((THRow)[row integerValue]) {
        case THRowStatus:
            cell.textLabel.text = THNetHookInstalled ? @"Хуки MTProto активны" : @"MTProto не найден";
            cell.detailTextLabel.text = THNetHookInstalled
                ? @"Плагины работают"
                : @"Класс MTRequestMessageService не найден — сетевые плагины не работают в этой версии Telegram";
            cell.imageView.image = [UIImage systemImageNamed:THNetHookInstalled ? @"checkmark.shield.fill"
                                                                                : @"exclamationmark.triangle.fill"];
            cell.imageView.tintColor = THNetHookInstalled ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
            break;
        case THRowGhostMaster:
            cell.textLabel.text = @"Включить всё";
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
            cell.imageView.image = [UIImage systemImageNamed:@"eye.slash.fill"];
            cell.accessoryView = [self switchOn:[self ghostAllOn] tag:0 action:@selector(ghostMasterToggled:)];
            break;
        case THRowReadNow: {
            NSTimeInterval left = st.readUnlockRemaining;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.text = left > 0
                ? [NSString stringWithFormat:@"Чтение разрешено ещё %.0f с", ceil(left)]
                : [NSString stringWithFormat:@"Прочитать сейчас (%.0f с)", kReadUnlockSeconds];
            cell.detailTextLabel.text = @"Временно пропускает отметки о прочтении, чтобы прочитать нужный чат";
            break;
        }
        case THRowCustomRules: {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            NSArray *c = st.customBlocked;
            cell.textLabel.text = @"Блокируемые методы";
            cell.detailTextLabel.text = c.count ? [self hexList:c] : @"Нет";
            break;
        }
        case THRowLogSwitch:
            cell.textLabel.text = @"Журнал запросов";
            cell.detailTextLabel.text = @"Записывать последние 300 исходящих запросов";
            cell.accessoryView = [self switchOn:st.loggingEnabled tag:0 action:@selector(logToggled:)];
            break;
        case THRowLogOpen:
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = @"Открыть журнал";
            break;
        case THRowAbout: {
            NSString *tg = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"?";
            cell.textLabel.text = @"TeleHack 0.1.0";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Telegram %@ · открыть панель: зажать тремя пальцами", tg];
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    id row = _sections[ip.section].rows[ip.row];
    if (![row isKindOfClass:[NSNumber class]]) return;
    switch ((THRow)[row integerValue]) {
        case THRowReadNow:
            [[THSettings shared] unlockReadsFor:kReadUnlockSeconds];
            [tv reloadData];
            break;
        case THRowCustomRules: [self editCustomRules]; break;
        case THRowLogOpen: [self.navigationController pushViewController:[THLogViewController new] animated:YES]; break;
        default: break;
    }
}

#pragma mark Actions

- (void)featureToggled:(UISwitch *)sw {
    THFeature *f = [THFeatures all][(NSUInteger)sw.tag];
    [[THSettings shared] setBool:sw.on forKey:f.key];
    [self.tableView reloadData];
}

- (void)ghostMasterToggled:(UISwitch *)sw {
    for (THFeature *f in [THFeatures inSection:THSectionGhost])
        [[THSettings shared] setBool:sw.on forKey:f.key];
    [self.tableView reloadData];
}

- (void)logToggled:(UISwitch *)sw {
    [THSettings shared].loggingEnabled = sw.on;
}

- (NSString *)hexList:(NSArray<NSNumber *> *)list {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSNumber *n in list) [parts addObject:[NSString stringWithFormat:@"0x%08x", n.unsignedIntValue]];
    return [parts componentsJoinedByString:@", "];
}

- (void)editCustomRules {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Свои правила"
        message:@"Constructor ID через запятую, например: 0x58943ee2, 0x6628562c"
        preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = [self hexList:[THSettings shared].customBlocked];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current;
        tf.placeholder = @"0x00000000";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak UIAlertController *weakA = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *text = weakA.textFields.firstObject.text ?: @"";
        NSMutableArray *ids = [NSMutableArray array];
        NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@", \n;"];
        for (NSString *raw in [text componentsSeparatedByCharactersInSet:sep]) {
            if (!raw.length) continue;
            unsigned int v = 0;
            NSScanner *sc = [NSScanner scannerWithString:raw];
            if ([sc scanHexInt:&v] && sc.isAtEnd && v != 0 && ![ids containsObject:@(v)]) [ids addObject:@(v)];
        }
        [THSettings shared].customBlocked = ids;
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Log

@implementation THLogViewController {
    NSArray<THLogEntry *> *_entries;
    NSDateFormatter *_fmt;
}

- (instancetype)init { return [super initWithStyle:UITableViewStylePlain]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Журнал";
    _fmt = [NSDateFormatter new];
    _fmt.dateFormat = @"HH:mm:ss";
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(clear)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share:)],
    ];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self reload];
}

- (void)reload {
    _entries = [THLog entries];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}

- (void)clear { [THLog clear]; [self reload]; }

- (void)share:(UIBarButtonItem *)sender {
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[THLog exportText]]
                                                                     applicationActivities:nil];
    vc.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:vc animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return MAX(_entries.count, (NSUInteger)1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (!_entries.count) {
        cell.textLabel.text = [THSettings shared].loggingEnabled ? @"Пока пусто" : @"Журнал выключен";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }
    THLogEntry *e = _entries[ip.row];
    cell.textLabel.text = e.displayName;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    cell.textLabel.textColor = e.blocked ? [UIColor systemRedColor] : [UIColor labelColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu байт%@", [_fmt stringFromDate:e.date],
                                 (unsigned long)e.length, e.blocked ? @" · заблокирован" : @""];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!_entries.count) return;
    [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%08x", _entries[ip.row].constructor];
}

@end

#import "THSettingsEntry.h"
#import "THPanel.h"
#import "THFeatures.h"
#import "THSettings.h"
#import <objc/runtime.h>

#pragma mark - Settings screen detection

// Telegram's settings/account screen is Swift, so we don't touch its table.
// Instead we watch which view controller is on screen and, when it's the
// settings/"my profile" screen, pin a TeleHack banner above the tab bar.
static BOOL THIsSettingsController(UIViewController *vc) {
    NSString *name = NSStringFromClass(vc.class);
    // PeerInfoScreenImpl hosts both "Settings" and other profiles — only the
    // self/settings variant is interesting, but attaching to any of them is
    // harmless because the banner lives in the tab-bar window overlay.
    return [name containsString:@"SettingsController"] ||
           [name containsString:@"PeerInfoScreen"] ||
           [name containsString:@"AccountSettings"];
}

#pragma mark - Banner

@interface THBannerController : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) UIView *banner;
- (void)showInController:(UIViewController *)vc;
- (void)hide;
@end

@implementation THBannerController

+ (instancetype)shared {
    static THBannerController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (NSUInteger)activeCount {
    NSUInteger n = 0;
    for (THFeature *f in [THFeatures all]) if ([[THSettings shared] boolForKey:f.key]) n++;
    return n;
}

- (void)showInController:(UIViewController *)vc {
    UIView *host = vc.view;
    if (!host) return;

    UIView *existing = self.banner;
    if (existing && existing.superview) {
        if (existing.superview == host || [host isDescendantOfView:existing.superview]) {
            [self refresh];
            return;
        }
        [existing removeFromSuperview];
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    button.layer.cornerRadius = 12;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 16, 14, 16);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"puzzlepiece.extension.fill"]];
    icon.tintColor = vc.view.tintColor ?: [UIColor systemBlueColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *title = [UILabel new];
    title.text = @"TeleHack — плагины";
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *sub = [UILabel new];
    sub.tag = 991;
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = [UIColor tertiaryLabelColor];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.contentMode = UIViewContentModeScaleAspectFit;

    [button addSubview:icon];
    [button addSubview:title];
    [button addSubview:sub];
    [button addSubview:chevron];
    [host addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:16],
        [button.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [button.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-12],

        [icon.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:26],
        [icon.heightAnchor constraintEqualToConstant:26],

        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:button.topAnchor constant:12],

        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [sub.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],

        [chevron.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12],
    ]];

    self.banner = button;
    [self refresh];
}

- (void)refresh {
    UILabel *sub = [self.banner viewWithTag:991];
    if (![sub isKindOfClass:[UILabel class]]) return;
    NSUInteger n = [self activeCount];
    NSString *word = (n % 10 == 1 && n % 100 != 11) ? @"плагин"
                   : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) ? @"плагина" : @"плагинов";
    sub.text = n ? [NSString stringWithFormat:@"Включено %lu %@ · нажмите, чтобы настроить", (unsigned long)n, word]
                 : @"Все плагины выключены · нажмите, чтобы настроить";
}

- (void)hide {
    [self.banner removeFromSuperview];
    self.banner = nil;
}

- (void)open {
    UIView *v = self.banner;
    UIResponder *r = v;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    THPanelPresentFrom((UIViewController *)r);
}

@end

#pragma mark - Hooks

void THSettingsEntryInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method m = class_getInstanceMethod([UIViewController class], @selector(viewDidLayoutSubviews));
        if (!m) return;
        IMP original = method_getImplementation(m);
        IMP replacement = imp_implementationWithBlock(^(UIViewController *self) {
            ((void (*)(id, SEL))original)(self, @selector(viewDidLayoutSubviews));
            if (THIsSettingsController(self))
                [[THBannerController shared] showInController:self];
        });
        method_setImplementation(m, replacement);

        [[NSNotificationCenter defaultCenter] addObserverForName:THSettingsChangedNotification
            object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                [[THBannerController shared] refresh];
            }];
    });
}

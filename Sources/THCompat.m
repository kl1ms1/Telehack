#import "THCompat.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSString *THFallbackRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *base = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
        root = [base stringByAppendingPathComponent:@"TeleHackGroup"];
    });
    return root;
}

static NSURL *THFallbackContainer(NSString *groupIdentifier) {
    // One stable sub-directory per requested group id, inside our own sandbox.
    NSString *safe = [groupIdentifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *path = [THFallbackRoot() stringByAppendingPathComponent:safe ?: @"default"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES attributes:nil error:&error];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

void THCompatInstall(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Crash guard: set a "launch in progress" flag now and clear it once the app
    // becomes active. If a previous launch set it and never cleared it, that
    // launch crashed without the container — so we permanently require THCompat.
    BOOL crashedLastLaunch = [d boolForKey:@"telehack.launchPending"];
    [d setBool:YES forKey:@"telehack.launchPending"];
    [d synchronize];
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
        usingBlock:^(NSNotification *n) {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"telehack.launchPending"];
        }];

    BOOL compatRequired = [d boolForKey:@"telehack.compatRequired"];
    if (crashedLastLaunch) {
        compatRequired = YES;
        [d setBool:YES forKey:@"telehack.compatRequired"];  // stick with it from now on
    }

    // 0.0.9 diagnostic: run WITHOUT the container override to test whether it is
    // what blocks login. If a launch without it crashes, the guard above turns it
    // back on permanently on the next launch.
    if (!compatRequired) {
        return;  // THCompat disabled this launch
    }

    // Only needed when we are NOT the official Telegram bundle id. If we are the
    // real app (jailbreak install), leave its real shared container untouched.
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    BOOL isOfficial = [bundleID isEqualToString:@"ph.telegra.Telegraph"];
    if (isOfficial) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [NSFileManager class];
        SEL sel = @selector(containerURLForSecurityApplicationGroupIdentifier:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        __block NSURL *(*original)(id, SEL, NSString *) = (void *)method_getImplementation(m);
        IMP replacement = imp_implementationWithBlock(^NSURL *(id self, NSString *group) {
            NSURL *real = original(self, sel, group);
            if (real) return real;            // entitlement granted — use it
            return THFallbackContainer(group); // resigned copy — use fallback
        });
        method_setImplementation(m, replacement);
    });
}

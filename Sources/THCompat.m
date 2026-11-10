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
    // 0.0.9 proved Telegram cannot even render without a shared container
    // (black screen), so THCompat is mandatory on a resigned copy. Always
    // install it for a non-official bundle id.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // Clear any leftover test flags from 0.0.7–0.0.9 so nothing keeps it off.
    [d setBool:NO forKey:@"telehack.launchPending"];
    [d setBool:NO forKey:@"telehack.skipCompatOnce"];

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

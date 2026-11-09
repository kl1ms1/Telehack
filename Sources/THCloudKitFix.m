#import "THCloudKitFix.h"
#import <objc/runtime.h>
#import <objc/message.h>

// A copy resigned with a non-Telegram team aborts on launch when Telegram asks
// CloudKit for its iCloud container: CloudKit validates the iCloud entitlement
// inside a dispatch_once and raises an NSException. That exception cannot be
// caught — it unwinds through libdispatch's _dispatch_client_callout, which is
// compiled without exception support, so it hits std::terminate -> abort before
// any @catch above it runs.
//
// So we must stop the throw at the source: our hooked CKContainer factories
// return nil WITHOUT calling the original, so CloudKit's throwing one-time
// init never runs. Telegram then behaves as if iCloud is unavailable.

static id THNilContainerDefault(id self, SEL _cmd) {
    NSLog(@"[TeleHack] CKContainer defaultContainer -> nil (iCloud disabled on resigned copy)");
    return nil;
}

static id THNilContainerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    NSLog(@"[TeleHack] CKContainer containerWithIdentifier:%@ -> nil (iCloud disabled)", identifier);
    return nil;
}

static void THInstallOnce(void) {
    Class CKContainer = objc_getClass("CKContainer");
    if (!CKContainer) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method def = class_getClassMethod(CKContainer, NSSelectorFromString(@"defaultContainer"));
        if (def) method_setImplementation(def, (IMP)THNilContainerDefault);

        Method byId = class_getClassMethod(CKContainer, NSSelectorFromString(@"containerWithIdentifier:"));
        if (byId) method_setImplementation(byId, (IMP)THNilContainerWithIdentifier);
    });
}

void THCloudKitFixInstall(void) {
    THInstallOnce();
    if (!objc_getClass("CKContainer")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ THInstallOnce(); });
    }
}

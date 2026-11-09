#import "THCloudKitFix.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP gOrigDefault;
static IMP gOrigWithIdentifier;

static id THSafeDefaultContainer(id self, SEL _cmd) {
    @try {
        return ((id (*)(id, SEL))gOrigDefault)(self, _cmd);
    } @catch (NSException *e) {
        NSLog(@"[TeleHack] suppressed CloudKit defaultContainer exception: %@", e.reason);
        return nil;
    }
}

static id THSafeContainerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    @try {
        return ((id (*)(id, SEL, NSString *))gOrigWithIdentifier)(self, _cmd, identifier);
    } @catch (NSException *e) {
        NSLog(@"[TeleHack] suppressed CloudKit container(%@) exception: %@", identifier, e.reason);
        return nil;
    }
}

static void THInstallOnce(void) {
    Class CKContainer = objc_getClass("CKContainer");
    if (!CKContainer) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method def = class_getClassMethod(CKContainer, NSSelectorFromString(@"defaultContainer"));
        if (def && !gOrigDefault) {
            gOrigDefault = method_getImplementation(def);
            method_setImplementation(def, (IMP)THSafeDefaultContainer);
        }
        Method byId = class_getClassMethod(CKContainer, NSSelectorFromString(@"containerWithIdentifier:"));
        if (byId && !gOrigWithIdentifier) {
            gOrigWithIdentifier = method_getImplementation(byId);
            method_setImplementation(byId, (IMP)THSafeContainerWithIdentifier);
        }
    });
}

void THCloudKitFixInstall(void) {
    // CloudKit is normally already mapped at launch; if not, install as soon as
    // the class exists (CKContainer is first touched well after startup).
    THInstallOnce();
    if (!objc_getClass("CKContainer")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ THInstallOnce(); });
    }
}

// TeleHack — plugins for Telegram iOS.
//
// All network plugins work at the MTProto level: every outgoing API call in
// Telegram goes through -[MTRequestMessageService addRequest:] (MtProtoKit is
// Objective-C, so it is hookable even though the rest of the app is Swift).
// The request payload starts with the TL constructor ID of the function, which
// is what THNetFilter matches against.

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "THNetFilter.h"
#import "THPanel.h"
#import "THSettingsEntry.h"
#import "THCompat.h"
#import "THCloudKitFix.h"

%group MTProto

%hook MTRequestMessageService

- (void)addRequest:(id)request {
    if (request && THNetFilterShouldDrop(request)) return;
    %orig;
}

%end

%end

// Master switch: the MTProto request hook is only installed when the user has
// explicitly enabled it. Default OFF while we confirm it is not what breaks
// login on a resigned copy. Ghost-mode plugins need this ON (and a relaunch).
static BOOL THNetHookAllowed(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"telehack.netHook"];
}

static void THTryInstallNetHook(void) {
    static dispatch_once_t once;
    if (THNetHookInstalled || !THNetHookAllowed() || !objc_getClass("MTRequestMessageService")) return;
    dispatch_once(&once, ^{
        %init(MTProto);
        THNetHookInstalled = YES;
    });
}

static void THImageAdded(const struct mach_header *mh, intptr_t slide) {
    THTryInstallNetHook();
    THCloudKitFixInstall();  // in case CloudKit is mapped after us
}

%ctor {
    @autoreleasepool {
        // Let a side-loaded copy with a changed bundle id run next to the
        // official Telegram (must run before Telegram reads its containers).
        THCompatInstall();

        // Stop a resigned copy from aborting on CloudKit's entitlement check.
        THCloudKitFixInstall();

        THTryInstallNetHook();
        // MtProtoKit may live in a framework that is mapped after us.
        if (!THNetHookInstalled) _dyld_register_func_for_add_image(THImageAdded);

        // UI only in the app itself, not in share/notification extensions.
        if ([[NSBundle mainBundle].bundlePath hasSuffix:@".app"]) {
            THPanelInstall();
            THSettingsEntryInstall();
        }
    }
}

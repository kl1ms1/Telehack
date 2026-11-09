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

%group MTProto

%hook MTRequestMessageService

- (void)addRequest:(id)request {
    if (request && THNetFilterShouldDrop(request)) return;
    %orig;
}

%end

%end

static void THTryInstallNetHook(void) {
    static dispatch_once_t once;
    if (THNetHookInstalled || !objc_getClass("MTRequestMessageService")) return;
    dispatch_once(&once, ^{
        %init(MTProto);
        THNetHookInstalled = YES;
    });
}

static void THImageAdded(const struct mach_header *mh, intptr_t slide) {
    THTryInstallNetHook();
}

%ctor {
    @autoreleasepool {
        // Let a side-loaded copy with a changed bundle id run next to the
        // official Telegram (must run before Telegram reads its containers).
        THCompatInstall();

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

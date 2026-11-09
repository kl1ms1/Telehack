#import <UIKit/UIKit.h>

/// Installs a TeleHack banner pinned to the bottom of Telegram's own Settings
/// screen (tap to open the plugin panel) and keeps a side-loaded copy from
/// crashing when it runs next to the official Telegram under a different
/// bundle identifier.
void THSettingsEntryInstall(void);

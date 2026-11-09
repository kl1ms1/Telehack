#import <Foundation/Foundation.h>

/// Makes a side-loaded Telegram copy (installed under a different bundle id,
/// so it can coexist with the official app) survive startup even though its
/// provisioning profile does not grant Telegram's shared App Group.
///
/// Telegram force-unwraps the App Group container URL on launch; for a resigned
/// copy that URL is nil, which crashes the app before it ever shows a screen.
/// We return a private per-app fallback directory instead, so the copy keeps
/// all of its data in its own sandbox and runs completely independently.
void THCompatInstall(void);

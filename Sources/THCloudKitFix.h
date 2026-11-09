#import <Foundation/Foundation.h>

/// A copy resigned with a different team hits an uncaught CloudKit exception on
/// launch: Telegram asks for its iCloud container (iCloud.ph.telegra.Telegraph),
/// which belongs to Telegram's team, and CloudKit raises "no entitlement for
/// this container" -> SIGABRT before the UI appears.
///
/// We wrap the CKContainer entry points so that exception is swallowed and the
/// app behaves as if iCloud is simply unavailable (the same state as a user who
/// is not signed into iCloud), which Telegram handles gracefully.
void THCloudKitFixInstall(void);

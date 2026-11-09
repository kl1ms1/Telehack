#import <Foundation/Foundation.h>

/// Called for every outgoing MTRequest. Returns YES if the request must be
/// silently dropped instead of being sent to Telegram servers.
BOOL THNetFilterShouldDrop(id request);

/// YES once the MTProto hook has been installed.
extern BOOL THNetHookInstalled;

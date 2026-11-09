#import <UIKit/UIKit.h>

/// Installs the 3-finger long-press gesture that opens the TeleHack panel.
void THPanelInstall(void);

@interface THPanelViewController : UITableViewController
@end

@interface THLogViewController : UITableViewController
@end

/// Present the panel from a specific view controller (used by the Settings banner).
void THPanelPresentFrom(UIViewController *presenter);

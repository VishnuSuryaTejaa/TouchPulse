#import <AppKit/AppKit.h>

@interface TPControlCenterWindowController : NSWindowController <NSWindowDelegate>

- (void)syncUI;
- (void)showAndFocus;

@end

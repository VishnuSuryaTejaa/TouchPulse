#import <AppKit/AppKit.h>

@interface TPTouchBarCanvasView : NSView
@property (nonatomic, assign) BOOL isHardwareTouchBar;
- (instancetype)initAsHardwareTouchBar:(BOOL)isHardware;
@end

@interface TPTouchBarController : NSObject <NSTouchBarDelegate>

@property (nonatomic, assign) BOOL alwaysOnActive;
@property (nonatomic, assign) BOOL fullWidthMode;       // NO = App Region + Control Strip, YES = Full-Width Cinema
@property (nonatomic, assign) BOOL showCloseBox;        // macOS left 'X' close button in modal mode
@property (nonatomic, strong, readonly) NSTouchBar *touchBar;
@property (nonatomic, copy, nullable) void (^onPresentationChanged)(BOOL active);

+ (instancetype)shared;

- (void)installControlStripItem;
- (void)uninstallControlStripItem;

- (void)presentSystemTouchBar;
- (void)dismissSystemTouchBar;
- (void)toggleSystemTouchBar;
- (void)refreshPresentation;

// Also provides a standard NSTouchBar for the Control Center window when App-Only mode is used
- (NSTouchBar *)makeWindowTouchBar;

@end

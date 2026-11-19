#import "TPTouchBarController.h"
#import "TPEngine.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSTouchBarItemIdentifier const kTPTrayIdentifier   = @"com.touchpulse.controlstrip.tray";
static NSTouchBarItemIdentifier const kTPCanvasIdentifier = @"com.touchpulse.canvas.item";

typedef void (*TPDFRCloseBoxFn)(BOOL);
typedef void (*TPDFRPresenceFn)(NSTouchBarItemIdentifier, BOOL);
typedef void (*TPMsgPresentPlacement)(id, SEL, NSTouchBar *, long long, NSTouchBarItemIdentifier);
typedef void (*TPMsgPresentSimple)(id, SEL, NSTouchBar *, NSTouchBarItemIdentifier);
typedef void (*TPMsgTouchBarOnly)(id, SEL, NSTouchBar *);
typedef void (*TPMsgTrayItemOnly)(id, SEL, NSTouchBarItem *);

#pragma mark - TPTouchBarCanvasView

@interface TPTouchBarCanvasView () {
    NSMutableDictionary<id<NSCopying>, NSNumber *> *_touchMap;
    uint64_t _nextTouchID;
}
@end

@implementation TPTouchBarCanvasView

- (instancetype)initAsHardwareTouchBar:(BOOL)isHardware {
    self = [super initWithFrame:NSMakeRect(0, 0, isHardware ? 1005.0 : 680.0, 30.0)];
    if (self) {
        _isHardwareTouchBar = isHardware;
        _touchMap = [NSMutableDictionary dictionary];
        _nextTouchID = 1;
        self.allowedTouchTypes = NSTouchTypeMaskDirect;
        self.wantsRestingTouches = NO;

        if (isHardware) {
            self.translatesAutoresizingMaskIntoConstraints = NO;
            [self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            [self.heightAnchor constraintEqualToConstant:30.0].active = YES;
        }
    }
    return self;
}

- (NSSize)intrinsicContentSize {
    if (_isHardwareTouchBar) {
        return NSMakeSize(1085.0, 30.0);
    }
    return NSMakeSize(NSViewNoIntrinsicMetric, 30.0);
}

- (BOOL)isOpaque {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [[TPEngine shared] registerDisplayView:self];
    } else {
        [[TPEngine shared] unregisterDisplayView:self];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
    if (!ctx) return;
    [[TPEngine shared] renderInContext:ctx size:self.bounds.size];
}

#pragma mark - Direct Hardware Touch Bar Multi-Touch Events

- (uint64_t)idForTouch:(NSTouch *)touch create:(BOOL)create {
    id<NSCopying> key = touch.identity;
    if (!key) return 0;
    NSNumber *num = _touchMap[key];
    if (!num && create) {
        num = @(_nextTouchID++);
        _touchMap[key] = num;
    }
    return num ? num.unsignedLongLongValue : 0;
}

- (void)touchesBeganWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches = [event touchesMatchingPhase:NSTouchPhaseBegan inView:self];
    for (NSTouch *t in touches) {
        uint64_t tid = [self idForTouch:t create:YES];
        NSPoint loc = [t locationInView:self];
        [[TPEngine shared] handleTouchBeganID:tid point:loc inSize:self.bounds.size];
    }
}

- (void)touchesMovedWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches = [event touchesMatchingPhase:NSTouchPhaseMoved inView:self];
    for (NSTouch *t in touches) {
        uint64_t tid = [self idForTouch:t create:YES];
        NSPoint loc = [t locationInView:self];
        [[TPEngine shared] handleTouchMovedID:tid point:loc inSize:self.bounds.size];
    }
}

- (void)touchesEndedWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches = [event touchesMatchingPhase:NSTouchPhaseEnded inView:self];
    for (NSTouch *t in touches) {
        uint64_t tid = [self idForTouch:t create:NO];
        NSPoint loc = [t locationInView:self];
        if (tid) {
            [[TPEngine shared] handleTouchEndedID:tid point:loc inSize:self.bounds.size];
            if (t.identity) [_touchMap removeObjectForKey:t.identity];
        }
    }
}

- (void)touchesCancelledWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches = [event touchesMatchingPhase:NSTouchPhaseCancelled inView:self];
    for (NSTouch *t in touches) {
        uint64_t tid = [self idForTouch:t create:NO];
        NSPoint loc = [t locationInView:self];
        if (tid) {
            [[TPEngine shared] handleTouchEndedID:tid point:loc inSize:self.bounds.size];
            if (t.identity) [_touchMap removeObjectForKey:t.identity];
        }
    }
}

#pragma mark - Mouse Input (for the Live Interactive Control Center Mirror!)

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    [[TPEngine shared] handleTouchBeganID:0xF00D0001ULL point:loc inSize:self.bounds.size];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    [[TPEngine shared] handleTouchMovedID:0xF00D0001ULL point:loc inSize:self.bounds.size];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    [[TPEngine shared] handleTouchEndedID:0xF00D0001ULL point:loc inSize:self.bounds.size];
}

@end

#pragma mark - TPTouchBarController

@interface TPTouchBarController () {
    void *_dfrHandle;
    TPDFRCloseBoxFn _setCloseBoxFn;
    TPDFRPresenceFn _setPresenceFn;

    NSCustomTouchBarItem *_trayItem;
    NSTouchBar *_modalBar;
    TPTouchBarCanvasView *_modalCanvasView;
    BOOL _trayInstalled;
}
@end

@implementation TPTouchBarController

+ (instancetype)shared {
    static TPTouchBarController *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[TPTouchBarController alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fullWidthMode = NO;
        _showCloseBox = YES;
        [self loadDFRPrivateAPIs];
        [self buildModalTouchBar];

        // Re-present Touch Bar smoothly after Mac wake from sleep!
        NSNotificationCenter *wsNC = [[NSWorkspace sharedWorkspace] notificationCenter];
        [wsNC addObserver:self selector:@selector(handleSystemWake:) name:NSWorkspaceDidWakeNotification object:nil];
        [wsNC addObserver:self selector:@selector(handleSystemWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [self dismissSystemTouchBar];
    [self uninstallControlStripItem];
}

- (NSTouchBar *)touchBar {
    return _modalBar;
}

- (void)loadDFRPrivateAPIs {
    _dfrHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    if (_dfrHandle) {
        _setCloseBoxFn = (TPDFRCloseBoxFn)dlsym(_dfrHandle, "DFRSystemModalShowsCloseBoxWhenFrontMost");
        _setPresenceFn = (TPDFRPresenceFn)dlsym(_dfrHandle, "DFRElementSetControlStripPresenceForIdentifier");
    }
}

- (void)buildModalTouchBar {
    _modalBar = [[NSTouchBar alloc] init];
    _modalBar.delegate = self;
    _modalBar.defaultItemIdentifiers = @[ kTPCanvasIdentifier ];
}

- (NSImage *)makeControlStripGlyph {
    NSSize sz = NSMakeSize(20, 20);
    NSImage *img = [[NSImage alloc] initWithSize:sz];
    [img lockFocus];
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;

    // Vibrant neon pulse bolt inside subtle ring
    CGContextSetRGBStrokeColor(ctx, 0.0, 0.92, 1.0, 0.95);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(2, 2, 16, 16));

    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 11.2, 15.5);
    CGContextAddLineToPoint(ctx, 6.8, 9.6);
    CGContextAddLineToPoint(ctx, 10.2, 9.6);
    CGContextAddLineToPoint(ctx, 8.8, 4.5);
    CGContextAddLineToPoint(ctx, 13.4, 10.4);
    CGContextAddLineToPoint(ctx, 10.0, 10.4);
    CGContextClosePath(ctx);
    CGContextSetRGBFillColor(ctx, 1.0, 0.25, 0.72, 1.0);
    CGContextFillPath(ctx);

    [img unlockFocus];
    [img setTemplate:NO];
    return img;
}

- (void)installControlStripItem {
    if (_trayInstalled) return;

    _trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:kTPTrayIdentifier];
    NSButton *btn = [NSButton buttonWithImage:[self makeControlStripGlyph]
                                       target:self
                                       action:@selector(toggleSystemTouchBar)];
    btn.bezelColor = [NSColor colorWithRed:0.12 green:0.14 blue:0.22 alpha:1.0];
    _trayItem.view = btn;

    SEL addSel = NSSelectorFromString(@"addSystemTrayItem:");
    if ([NSTouchBarItem respondsToSelector:addSel]) {
        ((TPMsgTrayItemOnly)objc_msgSend)([NSTouchBarItem class], addSel, _trayItem);
    }
    if (_setPresenceFn) {
        _setPresenceFn(kTPTrayIdentifier, YES);
    }
    _trayInstalled = YES;
}

- (void)uninstallControlStripItem {
    if (!_trayInstalled) return;
    if (_setPresenceFn) {
        _setPresenceFn(kTPTrayIdentifier, NO);
    }
    SEL remSel = NSSelectorFromString(@"removeSystemTrayItem:");
    if (_trayItem && [NSTouchBarItem respondsToSelector:remSel]) {
        ((TPMsgTrayItemOnly)objc_msgSend)([NSTouchBarItem class], remSel, _trayItem);
    }
    _trayItem = nil;
    _trayInstalled = NO;
}

- (void)presentSystemTouchBar {
    [self installControlStripItem];

    if (_setCloseBoxFn) {
        _setCloseBoxFn(_showCloseBox);
    }

    SEL placementSel = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    SEL simpleSel    = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");

    if ([NSTouchBar respondsToSelector:placementSel]) {
        long long placement = _fullWidthMode ? 1 : 0;
        ((TPMsgPresentPlacement)objc_msgSend)([NSTouchBar class], placementSel, _modalBar, placement, kTPTrayIdentifier);
    } else if ([NSTouchBar respondsToSelector:simpleSel]) {
        ((TPMsgPresentSimple)objc_msgSend)([NSTouchBar class], simpleSel, _modalBar, kTPTrayIdentifier);
    }

    _alwaysOnActive = YES;
    if (_modalCanvasView) {
        [[TPEngine shared] registerDisplayView:_modalCanvasView];
    }
    if (self.onPresentationChanged) self.onPresentationChanged(YES);
}

- (void)dismissSystemTouchBar {
    SEL dismissSel = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if (_modalBar && [NSTouchBar respondsToSelector:dismissSel]) {
        ((TPMsgTouchBarOnly)objc_msgSend)([NSTouchBar class], dismissSel, _modalBar);
    }
    _alwaysOnActive = NO;
    if (_modalCanvasView) {
        [[TPEngine shared] unregisterDisplayView:_modalCanvasView];
    }
    if (self.onPresentationChanged) self.onPresentationChanged(NO);
}

- (void)toggleSystemTouchBar {
    if (_alwaysOnActive) {
        [self dismissSystemTouchBar];
    } else {
        [self presentSystemTouchBar];
    }
}

- (void)refreshPresentation {
    if (!_alwaysOnActive) return;
    // Re-apply placement / close box cleanly
    SEL dismissSel = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if (_modalBar && [NSTouchBar respondsToSelector:dismissSel]) {
        ((TPMsgTouchBarOnly)objc_msgSend)([NSTouchBar class], dismissSel, _modalBar);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self presentSystemTouchBar];
    });
}

- (void)handleSystemWake:(NSNotification *)note {
    if (!_alwaysOnActive) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.alwaysOnActive) {
            [self presentSystemTouchBar];
        }
    });
}

#pragma mark - NSTouchBarDelegate

- (nullable NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if ([identifier isEqualToString:kTPCanvasIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        TPTouchBarCanvasView *canvas = [[TPTouchBarCanvasView alloc] initAsHardwareTouchBar:YES];
        item.view = canvas;
        if (touchBar == _modalBar) {
            _modalCanvasView = canvas;
            if (_alwaysOnActive) {
                [[TPEngine shared] registerDisplayView:canvas];
            }
        }
        return item;
    }
    return nil;
}

- (NSTouchBar *)makeWindowTouchBar {
    NSTouchBar *bar = [[NSTouchBar alloc] init];
    bar.delegate = self;
    bar.defaultItemIdentifiers = @[ kTPCanvasIdentifier ];
    return bar;
}

@end

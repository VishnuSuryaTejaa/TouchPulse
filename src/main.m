#import <AppKit/AppKit.h>
#import "TPCommon.h"
#import "TPEngine.h"
#import "TPAudioEngine.h"
#import "TPSystemMonitor.h"
#import "TPTouchBarController.h"
#import "TPControlCenterWindow.h"

@interface TPAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) TPControlCenterWindowController *controlCenter;
@end

@implementation TPAppDelegate

- (NSImage *)makeMenuBarIcon {
    NSSize sz = NSMakeSize(18, 18);
    NSImage *img = [[NSImage alloc] initWithSize:sz];
    [img lockFocus];
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;

    // Crisp monochrome template icon (adapts to light & dark macOS menu bars!)
    CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1.0);
    CGContextSetLineWidth(ctx, 1.4);
    TPDrawRoundedRect(ctx, CGRectMake(1.5, 4.0, 15.0, 10.0), 3.0);
    CGContextStrokePath(ctx);

    // Mini lightning / pulse waveform inside the Touch Bar outline
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 4.0, 9.0);
    CGContextAddLineToPoint(ctx, 6.8, 9.0);
    CGContextAddLineToPoint(ctx, 8.2, 12.2);
    CGContextAddLineToPoint(ctx, 10.0, 5.8);
    CGContextAddLineToPoint(ctx, 11.4, 9.0);
    CGContextAddLineToPoint(ctx, 14.0, 9.0);
    CGContextSetLineWidth(ctx, 1.45);
    CGContextStrokePath(ctx);

    [img unlockFocus];
    [img setTemplate:YES];
    return img;
}

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TouchPulse"];
    [appMenu addItemWithTitle:@"Open Control Center" action:@selector(openControlCenter:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Toggle Always-On Touch Bar" action:@selector(toggleAlwaysOn:) keyEquivalent:@"t"];
    [appMenu addItemWithTitle:@"Toggle Full-Width Cinema" action:@selector(toggleFullWidth:) keyEquivalent:@"f"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide TouchPulse Window" action:@selector(performClose:) keyEquivalent:@"w"];
    [appMenu addItemWithTitle:@"Quit TouchPulse" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    [NSApp setMainMenu:mainMenu];
}

- (void)setupStatusBar {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [self makeMenuBarIcon];
    _statusItem.button.toolTip = @"TouchPulse — Touch Bar Playground";

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    _statusItem.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    TPEngine *eng = [TPEngine shared];
    TPTouchBarController *tbc = [TPTouchBarController shared];
    TPAudioEngine *au = [TPAudioEngine shared];
    TPSystemMonitor *sys = [TPSystemMonitor shared];

    NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"⚡ TouchPulse Touch Bar" action:nil keyEquivalent:@""];
    hdr.enabled = NO;
    [menu addItem:hdr];

    NSMenuItem *cc = [[NSMenuItem alloc] initWithTitle:@"Open Control Center & Live Mirror..."
                                               action:@selector(openControlCenter:)
                                        keyEquivalent:@""];
    [menu addItem:cc];
    [menu addItem:[NSMenuItem separatorItem]];

    // Always-On & Full-Width toggles
    NSMenuItem *alwaysOn = [[NSMenuItem alloc] initWithTitle:@"Always-On System Touch Bar"
                                                      action:@selector(toggleAlwaysOn:)
                                               keyEquivalent:@""];
    alwaysOn.state = tbc.alwaysOnActive ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:alwaysOn];

    NSMenuItem *fullW = [[NSMenuItem alloc] initWithTitle:@"Full-Width Cinema Mode"
                                                   action:@selector(toggleFullWidth:)
                                            keyEquivalent:@""];
    fullW.state = tbc.fullWidthMode ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:fullW];

    [menu addItem:[NSMenuItem separatorItem]];

    // All 8 Modes
    NSMenuItem *mHdr = [[NSMenuItem alloc] initWithTitle:@"Modes" action:nil keyEquivalent:@""];
    mHdr.enabled = NO;
    [menu addItem:mHdr];

    for (NSInteger i = 0; i < TPModeCount; i++) {
        NSString *title = [NSString stringWithFormat:@"%@  %@", TPModeSymbol((TPMode)i), TPModeName((TPMode)i)];
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:@selector(selectModeItem:) keyEquivalent:@""];
        it.tag = i;
        it.state = (eng.mode == (TPMode)i) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:it];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // Theme submenu
    NSMenuItem *themeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Color Palette" action:nil keyEquivalent:@""];
    NSMenu *themeSub = [[NSMenu alloc] init];
    for (NSInteger t = 0; t < TPThemeCount; t++) {
        NSMenuItem *ti = [[NSMenuItem alloc] initWithTitle:TPThemeName((TPTheme)t)
                                                    action:@selector(selectThemeItem:)
                                             keyEquivalent:@""];
        ti.tag = t;
        ti.state = (eng.theme == (TPTheme)t) ? NSControlStateValueOn : NSControlStateValueOff;
        [themeSub addItem:ti];
    }
    themeMenuItem.submenu = themeSub;
    [menu addItem:themeMenuItem];

    // Sound, Live Mic, Keep Awake
    NSMenuItem *snd = [[NSMenuItem alloc] initWithTitle:@"Synth & SFX Sound" action:@selector(toggleSound:) keyEquivalent:@""];
    snd.state = au.soundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:snd];

    NSMenuItem *mic = [[NSMenuItem alloc] initWithTitle:@"Live Microphone FFT Spectrum" action:@selector(toggleMic:) keyEquivalent:@""];
    mic.state = au.micActive ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:mic];

    NSMenuItem *awake = [[NSMenuItem alloc] initWithTitle:@"Keep Awake (Prevent Display Sleep)" action:@selector(toggleKeepAwake:) keyEquivalent:@""];
    awake.state = sys.keepAwakeActive ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:awake];

    NSMenuItem *mute = [[NSMenuItem alloc] initWithTitle:@"Mute Mac System Audio" action:@selector(toggleSystemMute:) keyEquivalent:@""];
    mute.state = sys.systemMuted ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:mute];

    [menu addItemWithTitle:@"📸 Area Screenshot to Clipboard" action:@selector(takeSnap:) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit TouchPulse" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupMainMenu];
    [self setupStatusBar];

    [[TPSystemMonitor shared] startPolling];
    // Audio output engine starts lazily on the first touch/synth/SFX so idle audio power stays zero!

    _controlCenter = [[TPControlCenterWindowController alloc] init];

    __weak typeof(self) weakSelf = self;
    [TPEngine shared].onStateChanged = ^{
        [weakSelf.controlCenter syncUI];
    };
    [TPTouchBarController shared].onPresentationChanged = ^(BOOL active) {
        [weakSelf.controlCenter syncUI];
    };

    // Light up the real MacBook Pro Touch Bar immediately in Always-On System Mode!
    [[TPTouchBarController shared] installControlStripItem];
    [[TPTouchBarController shared] presentSystemTouchBar];

    // Show the sleek Control Center with live interactive Touch Bar mirror
    [_controlCenter showAndFocus];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // Keep running cleanly in the Menu Bar + Always-On Touch Bar when Control Center is closed!
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [_controlCenter showAndFocus];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[TPTouchBarController shared] dismissSystemTouchBar];
    [[TPTouchBarController shared] uninstallControlStripItem];
    [[TPSystemMonitor shared] stopPolling];
    [[TPSystemMonitor shared] setKeepAwake:NO];
    [[TPAudioEngine shared] stopAll];
}

#pragma mark - Menu Actions

- (void)openControlCenter:(id)sender {
    [_controlCenter showAndFocus];
}

- (void)toggleAlwaysOn:(id)sender {
    [[TPTouchBarController shared] toggleSystemTouchBar];
    [_controlCenter syncUI];
}

- (void)toggleFullWidth:(id)sender {
    TPTouchBarController *tbc = [TPTouchBarController shared];
    tbc.fullWidthMode = !tbc.fullWidthMode;
    if (tbc.alwaysOnActive) {
        [tbc refreshPresentation];
    }
    [_controlCenter syncUI];
}

- (void)selectModeItem:(NSMenuItem *)sender {
    [TPEngine shared].mode = (TPMode)sender.tag;
    if (![TPTouchBarController shared].alwaysOnActive) {
        [[TPTouchBarController shared] presentSystemTouchBar];
    }
    [_controlCenter syncUI];
}

- (void)selectThemeItem:(NSMenuItem *)sender {
    [TPEngine shared].theme = (TPTheme)sender.tag;
    [_controlCenter syncUI];
}

- (void)toggleSound:(id)sender {
    [TPAudioEngine shared].soundEnabled = ![TPAudioEngine shared].soundEnabled;
    [_controlCenter syncUI];
}

- (void)toggleMic:(id)sender {
    BOOL next = ![TPAudioEngine shared].micActive;
    if (next) [TPEngine shared].mode = TPModeSpectrum;
    [[TPAudioEngine shared] setMicEnabled:next];
    [_controlCenter syncUI];
}

- (void)toggleKeepAwake:(id)sender {
    [[TPSystemMonitor shared] toggleKeepAwake];
    [_controlCenter syncUI];
}

- (void)toggleSystemMute:(id)sender {
    [[TPSystemMonitor shared] toggleSystemMute];
    [_controlCenter syncUI];
}

- (void)takeSnap:(id)sender {
    [[TPSystemMonitor shared] takeClipboardScreenshot];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        TPAppDelegate *delegate = [[TPAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

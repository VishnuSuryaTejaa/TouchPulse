#import "TPControlCenterWindow.h"
#import "TPAudioEngine.h"
#import "TPCommon.h"
#import "TPEngine.h"
#import "TPSystemMonitor.h"
#import "TPTouchBarController.h"

#pragma mark - Custom Glowing Mode Card View

@interface TPModeCardView : NSView
@property(nonatomic, assign) TPMode mode;
@property(nonatomic, assign) BOOL selected;
@property(nonatomic, assign) BOOL hovered;
@property(nonatomic, copy) void (^onSelect)(TPMode mode);
@end

@implementation TPModeCardView

- (instancetype)initWithMode:(TPMode)mode {
  self = [super initWithFrame:NSMakeRect(0, 0, 175, 68)];
  if (self) {
    _mode = mode;
    NSTrackingArea *ta = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                      NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:ta];
  }
  return self;
}

- (void)mouseEntered:(NSEvent *)event {
  _hovered = YES;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
  _hovered = NO;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
  if (self.onSelect)
    self.onSelect(_mode);
}

- (void)drawRect:(NSRect)dirtyRect {
  CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
  if (!ctx)
    return;

  CGRect b = CGRectInset(self.bounds, 1.0, 1.0);
  TPRGBA accent = TPThemeColor([TPEngine shared].theme,
                               (float)_mode / (float)TPModeCount, 1.0f);

  TPDrawRoundedRect(ctx, b, 10.0);
  if (_selected) {
    CGContextSetRGBFillColor(ctx, accent.r * 0.22 + 0.05,
                             accent.g * 0.22 + 0.06, accent.b * 0.22 + 0.09,
                             0.96);
  } else if (_hovered) {
    CGContextSetRGBFillColor(ctx, 0.14, 0.16, 0.22, 0.95);
  } else {
    CGContextSetRGBFillColor(ctx, 0.10, 0.11, 0.16, 0.88);
  }
  CGContextFillPath(ctx);

  TPDrawRoundedRect(ctx, CGRectInset(b, 0.5, 0.5), 9.5);
  if (_selected) {
    CGContextSetRGBStrokeColor(ctx, accent.r, accent.g, accent.b, 0.96);
    CGContextSetLineWidth(ctx, 1.8);
  } else if (_hovered) {
    CGContextSetRGBStrokeColor(ctx, accent.r, accent.g, accent.b, 0.45);
    CGContextSetLineWidth(ctx, 1.1);
  } else {
    CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.10);
    CGContextSetLineWidth(ctx, 1.0);
  }
  CGContextStrokePath(ctx);

  // Icon badge
  CGRect iconR = CGRectMake(11.0, b.size.height - 34.0, 24.0, 24.0);
  TPDrawRoundedRect(ctx, iconR, 6.0);
  CGContextSetRGBFillColor(ctx, accent.r, accent.g, accent.b,
                           _selected ? 0.28 : 0.14);
  CGContextFillPath(ctx);

  NSString *sym = TPModeSymbol(_mode);
  CGSize ss = TPMeasureText(sym, 13.0, NSFontWeightBold, NO);
  TPDrawText(
      ctx, sym,
      CGPointMake(iconR.origin.x + (iconR.size.width - ss.width) * 0.5,
                  iconR.origin.y + (iconR.size.height - ss.height) * 0.5),
      13.0, NSFontWeightBold,
      [NSColor colorWithRed:accent.r green:accent.g blue:accent.b alpha:1.0],
      NO);

    // Shortcut key badge top-right (1..9, 0, -, =)
    static NSString *const kKeys[12] = { @"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"0",@"-",@"=" };
    NSString *num = (_mode >= 0 && _mode < 12) ? kKeys[_mode] : @"";
    TPDrawText(ctx, num, CGPointMake(b.size.width - 15.0, b.size.height - 19.0),
               9.0, NSFontWeightSemibold,
               [NSColor colorWithWhite:1.0 alpha:_selected ? 0.78 : 0.28], YES);

    // Mode Title
    TPDrawText(ctx, TPModeName(_mode),
               CGPointMake(40.0, b.size.height - 27.0),
               12.0, NSFontWeightBold, [NSColor whiteColor], NO);

    // Subtitle (wrapped cleanly inside card)
    NSGraphicsContext *prev = [NSGraphicsContext currentContext];
    NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext setCurrentContext:nsCtx];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.78 alpha:0.86],
        NSParagraphStyleAttributeName: ps
    };
    [TPModeSubtitle(_mode) drawInRect:NSMakeRect(10.0, 4.0, b.size.width - 20.0, 26.0) withAttributes:subAttrs];
    [NSGraphicsContext setCurrentContext:prev];
}

@end

#pragma mark - Custom Theme Swatch Pill

@interface TPThemePillView : NSView
@property(nonatomic, assign) TPTheme theme;
@property(nonatomic, assign) BOOL selected;
@property(nonatomic, copy) void (^onSelect)(TPTheme theme);
@end

@implementation TPThemePillView

- (instancetype)initWithTheme:(TPTheme)theme {
  self = [super initWithFrame:NSMakeRect(0, 0, 128, 28)];
  if (self) {
    _theme = theme;
  }
  return self;
}

- (void)mouseDown:(NSEvent *)event {
  if (self.onSelect)
    self.onSelect(_theme);
}

- (void)drawRect:(NSRect)dirtyRect {
  CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
  if (!ctx)
    return;

  CGRect b = CGRectInset(self.bounds, 1.0, 1.0);
  TPRGBA c0 = TPThemeColor(_theme, 0.05f, 1.0f);
  TPRGBA c1 = TPThemeColor(_theme, 0.55f, 1.0f);

  TPDrawRoundedRect(ctx, b, 7.0);
  CGContextSetRGBFillColor(ctx, 0.11, 0.12, 0.17, 0.94);
  CGContextFillPath(ctx);

  TPDrawRoundedRect(ctx, CGRectInset(b, 0.5, 0.5), 6.5);
  if (_selected) {
    CGContextSetRGBStrokeColor(ctx, c0.r, c0.g, c0.b, 0.95);
    CGContextSetLineWidth(ctx, 1.7);
  } else {
    CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.12);
    CGContextSetLineWidth(ctx, 1.0);
  }
  CGContextStrokePath(ctx);

  // Two mini color dots
  CGContextSetRGBFillColor(ctx, c0.r, c0.g, c0.b, 1.0);
  CGContextFillEllipseInRect(ctx, CGRectMake(9, 9, 9, 9));
  CGContextSetRGBFillColor(ctx, c1.r, c1.g, c1.b, 1.0);
  CGContextFillEllipseInRect(ctx, CGRectMake(16, 9, 9, 9));

  TPDrawText(ctx, TPThemeName(_theme), CGPointMake(30.0, 7.0), 10.5,
             _selected ? NSFontWeightBold : NSFontWeightMedium,
             [NSColor colorWithWhite:1.0 alpha:_selected ? 1.0 : 0.80], NO);
}

@end

#pragma mark - Key-Aware Window Subclass

@interface TPMainWindow : NSWindow
@end

@implementation TPMainWindow
- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    if (chars.length == 1) {
        unichar ch = [chars characterAtIndex:0];
        if (ch >= '1' && ch <= '9') {
            [[TPEngine shared] setMode:(TPMode)(ch - '1')];
            return;
        }
        if (ch == '0') { [[TPEngine shared] setMode:(TPMode)9]; return; }
        if (ch == '-') { [[TPEngine shared] setMode:(TPMode)10]; return; }
        if (ch == '=') { [[TPEngine shared] setMode:(TPMode)11]; return; }
        if (ch == ' ') {
            if ([TPEngine shared].mode == TPModeRunner) {
                [[TPEngine shared] handleTouchBeganID:0x59ACEULL point:CGPointMake(200, 15) inSize:CGSizeMake(700, 30)];
                [[TPEngine shared] handleTouchEndedID:0x59ACEULL point:CGPointMake(200, 15) inSize:CGSizeMake(700, 30)];
                return;
            }
        }
        if (ch == 't' || ch == 'T') {
            [[TPEngine shared] cycleNextTheme];
            return;
        }
    }
    [super keyDown:event];
}

- (NSTouchBar *)makeTouchBar {
  return [[TPTouchBarController shared] makeWindowTouchBar];
}
@end

#pragma mark - TPControlCenterWindowController

@interface TPControlCenterWindowController () {
  TPTouchBarCanvasView *_mirrorView;
  NSMutableArray<TPModeCardView *> *_modeCards;
  NSMutableArray<TPThemePillView *> *_themePills;

  NSButton *_alwaysOnCheck;
  NSButton *_fullWidthCheck;
  NSButton *_modePillCheck;
  NSButton *_mouseReactCheck;
  NSButton *_soundCheck;
  NSSlider *_volumeSlider;
  NSSlider *_speedSlider;
  NSPopUpButton *_scalePopup;
  NSButton *_micButton;
  NSTextField *_micStatusLabel;
  NSButton *_awakeButton;
  NSTextField *_liveStatusPill;
}
@end

@implementation TPControlCenterWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 860, 628);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView;
    TPMainWindow *win = [[TPMainWindow alloc] initWithContentRect:frame
                                                        styleMask:style
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    win.title = @"TouchPulse v2 — Touch Bar Playground & Power Deck";
    win.titlebarAppearsTransparent = YES;
    win.titleVisibility = NSWindowTitleHidden;
    win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    win.backgroundColor = [NSColor colorWithRed:0.06 green:0.065 blue:0.095 alpha:1.0];
    win.releasedWhenClosed = NO;
    [win center];

  self = [super initWithWindow:win];
  if (self) {
    win.delegate = self;
    _modeCards = [NSMutableArray array];
    _themePills = [NSMutableArray array];
    [self buildUI];
    [self syncUI];
  }
  return self;
}

- (NSTextField *)makeLabel:(NSString *)text
                      size:(CGFloat)sz
                    weight:(NSFontWeight)w
                     color:(NSColor *)col {
  NSTextField *tf = [NSTextField labelWithString:text];
  tf.font = [NSFont systemFontOfSize:sz weight:w];
  tf.textColor = col ?: [NSColor whiteColor];
  return tf;
}

- (void)buildUI {
    NSView *root = self.window.contentView;
    CGFloat W = 860.0;
    CGFloat H = 628.0;
    CGFloat pad = 22.0;

  // Subtle dark glass vibrancy backdrop
  NSVisualEffectView *bg =
      [[NSVisualEffectView alloc] initWithFrame:root.bounds];
  bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  bg.material = NSVisualEffectMaterialHUDWindow;
  bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
  bg.state = NSVisualEffectStateActive;
  [root addSubview:bg];

    // 1. Header Bar
    NSTextField *title = [self makeLabel:@"⚡ TouchPulse 2.0" size:20.0 weight:NSFontWeightHeavy color:[NSColor whiteColor]];
    title.frame = NSMakeRect(pad, H - 46, 210, 26);
    [root addSubview:title];

    NSTextField *tagline = [self makeLabel:@"Chaos Visuals, 808 Beatbox, Physics, Synth & Slidable Power Deck"
                                      size:11.5 weight:NSFontWeightMedium
                                     color:[NSColor colorWithWhite:0.72 alpha:1.0]];
    tagline.frame = NSMakeRect(pad + 190, H - 41, 440, 18);
    [root addSubview:tagline];

    _liveStatusPill = [self makeLabel:@"● TOUCH BAR LIVE" size:10.5 weight:NSFontWeightBold
                                color:[NSColor colorWithRed:0.18 green:0.98 blue:0.62 alpha:1.0]];
    _liveStatusPill.alignment = NSTextAlignmentRight;
    _liveStatusPill.frame = NSMakeRect(W - pad - 180, H - 41, 180, 18);
    [root addSubview:_liveStatusPill];

    // 2. Live Interactive Touch Bar Mirror Bezel
    NSView *bezel = [[NSView alloc] initWithFrame:NSMakeRect(pad, H - 114, W - pad * 2, 56)];
    bezel.wantsLayer = YES;
    bezel.layer.backgroundColor = [NSColor colorWithRed:0.03 green:0.03 blue:0.05 alpha:1.0].CGColor;
    bezel.layer.cornerRadius = 11.0;
    bezel.layer.borderWidth = 1.3;
    bezel.layer.borderColor = [NSColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.38].CGColor;
    [root addSubview:bezel];

    NSTextField *mirrorHint = [self makeLabel:@"LIVE TOUCH BAR MIRROR  •  Click, drag, flick, or slide Power HUD right here or on your Touch Bar"
                                         size:9.5 weight:NSFontWeightSemibold
                                        color:[NSColor colorWithWhite:0.55 alpha:1.0]];
    mirrorHint.frame = NSMakeRect(12, 39, bezel.frame.size.width - 24, 13);
    [bezel addSubview:mirrorHint];

  _mirrorView = [[TPTouchBarCanvasView alloc] initAsHardwareTouchBar:NO];
  _mirrorView.frame = NSMakeRect(10, 6, bezel.frame.size.width - 20, 30);
  _mirrorView.wantsLayer = YES;
  _mirrorView.layer.cornerRadius = 5.0;
  _mirrorView.layer.masksToBounds = YES;
  [bezel addSubview:_mirrorView];

    // 3. 3x4 Mode Card Grid (12 Modes!)
    NSTextField *modesHdr = [self makeLabel:@"12 MODES  (Keys 1–9, 0, -, =  •  Tap left pill on Touch Bar to cycle)"
                                       size:10.5 weight:NSFontWeightBold
                                      color:[NSColor colorWithWhite:0.58 alpha:1.0]];
    modesHdr.frame = NSMakeRect(pad, H - 138, 520, 15);
    [root addSubview:modesHdr];

    CGFloat cardGap = 9.0;
    CGFloat cardW = (W - pad * 2 - cardGap * 3) / 4.0;
    CGFloat cardH = 68.0;
    __weak typeof(self) weakSelf = self;

    for (NSInteger i = 0; i < TPModeCount; i++) {
        NSInteger row = i / 4;
        NSInteger col = i % 4;
        CGFloat cx = pad + col * (cardW + cardGap);
        CGFloat cy = (H - 214.0) - row * (cardH + cardGap);

    TPModeCardView *card = [[TPModeCardView alloc] initWithMode:(TPMode)i];
    card.frame = NSMakeRect(cx, cy, cardW, cardH);
    card.onSelect = ^(TPMode m) {
      [TPEngine shared].mode = m;
      [weakSelf syncUI];
    };
    [root addSubview:card];
    [_modeCards addObject:card];
  }

  // 4. Color Theme Swatches Row
  NSTextField *themeHdr =
      [self makeLabel:@"COLOR PALETTE  (Key T  •  Or 3-finger tap on Touch Bar)"
                 size:10.5
               weight:NSFontWeightBold
                color:[NSColor colorWithWhite:0.58 alpha:1.0]];
  themeHdr.frame = NSMakeRect(pad, 232, 420, 15);
  [root addSubview:themeHdr];

  CGFloat pillGap = 8.0;
  CGFloat pillW = (W - pad * 2 - pillGap * 4) / 5.0;
  for (NSInteger t = 0; t < TPThemeCount; t++) {
    TPThemePillView *pill = [[TPThemePillView alloc] initWithTheme:(TPTheme)t];
    pill.frame = NSMakeRect(pad + t * (pillW + pillGap), 198, pillW, 28);
    pill.onSelect = ^(TPTheme th) {
      [TPEngine shared].theme = th;
      [weakSelf syncUI];
    };
    [root addSubview:pill];
    [_themePills addObject:pill];
  }

    // 5. Two-Column Controls Container
    CGFloat colW = (W - pad * 2 - 14.0) * 0.5;
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(pad, 18, colW, 164)];
    leftPanel.wantsLayer = YES;
    leftPanel.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.04].CGColor;
    leftPanel.layer.cornerRadius = 10.0;
    leftPanel.layer.borderWidth = 1.0;
    leftPanel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [root addSubview:leftPanel];

    NSTextField *tbTitle = [self makeLabel:@"TOUCH BAR BEHAVIOR" size:10.0 weight:NSFontWeightBold
                                     color:[NSColor colorWithWhite:0.58 alpha:1.0]];
    tbTitle.frame = NSMakeRect(14, 140, 220, 14);
    [leftPanel addSubview:tbTitle];

    _alwaysOnCheck = [NSButton checkboxWithTitle:@"Always-On System Mode (stays active across all apps)"
                                          target:self action:@selector(onAlwaysOnToggle:)];
    _alwaysOnCheck.frame = NSMakeRect(14, 112, colW - 24, 20);
    [leftPanel addSubview:_alwaysOnCheck];

    _fullWidthCheck = [NSButton checkboxWithTitle:@"Full-Width Cinema Mode (edge-to-edge over Control Strip)"
                                           target:self action:@selector(onFullWidthToggle:)];
    _fullWidthCheck.frame = NSMakeRect(14, 86, colW - 24, 20);
    [leftPanel addSubview:_fullWidthCheck];

    _modePillCheck = [NSButton checkboxWithTitle:@"Show Quick Mode Switcher Pill on Left Edge"
                                          target:self action:@selector(onModePillToggle:)];
    _modePillCheck.frame = NSMakeRect(14, 60, colW - 24, 20);
    [leftPanel addSubview:_modePillCheck];

    _mouseReactCheck = [NSButton checkboxWithTitle:@"Cursor Reactivity (pet & plasma follow Mac mouse)"
                                            target:self action:@selector(onMouseReactToggle:)];
    _mouseReactCheck.frame = NSMakeRect(14, 34, colW - 24, 20);
    [leftPanel addSubview:_mouseReactCheck];

    NSTextField *spdLbl = [self makeLabel:@"Speed" size:11.0 weight:NSFontWeightMedium color:[NSColor colorWithWhite:0.78 alpha:1.0]];
    spdLbl.frame = NSMakeRect(14, 9, 50, 16);
    [leftPanel addSubview:spdLbl];

    _speedSlider = [NSSlider sliderWithValue:1.0 minValue:0.4 maxValue:2.0 target:self action:@selector(onSpeedChanged:)];
    _speedSlider.frame = NSMakeRect(66, 7, colW - 84, 20);
    [leftPanel addSubview:_speedSlider];

    // Right Panel: Audio, Synth, Live Mic & Quick Actions
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(pad + colW + 14.0, 18, colW, 164)];
    rightPanel.wantsLayer = YES;
    rightPanel.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.04].CGColor;
    rightPanel.layer.cornerRadius = 10.0;
    rightPanel.layer.borderWidth = 1.0;
    rightPanel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [root addSubview:rightPanel];

    NSTextField *auTitle = [self makeLabel:@"AUDIO, SYNTH & QUICK ACTIONS" size:10.0 weight:NSFontWeightBold
                                     color:[NSColor colorWithWhite:0.58 alpha:1.0]];
    auTitle.frame = NSMakeRect(14, 140, 250, 14);
    [rightPanel addSubview:auTitle];

    _soundCheck = [NSButton checkboxWithTitle:@"Synth & SFX Audio" target:self action:@selector(onSoundToggle:)];
    _soundCheck.frame = NSMakeRect(14, 112, 145, 20);
    [rightPanel addSubview:_soundCheck];

    _volumeSlider = [NSSlider sliderWithValue:0.72 minValue:0.0 maxValue:1.0 target:self action:@selector(onVolumeChanged:)];
    _volumeSlider.frame = NSMakeRect(166, 112, colW - 182, 20);
    [rightPanel addSubview:_volumeSlider];

    NSTextField *scLbl = [self makeLabel:@"Synth Scale:" size:11.0 weight:NSFontWeightMedium color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    scLbl.frame = NSMakeRect(14, 84, 78, 18);
    [rightPanel addSubview:scLbl];

    _scalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(94, 80, colW - 110, 24) pullsDown:NO];
    for (NSInteger s = 0; s < TPSynthScaleCount; s++) {
        [_scalePopup addItemWithTitle:TPSynthScaleName((TPSynthScale)s)];
    }
    _scalePopup.target = self;
    _scalePopup.action = @selector(onScaleChanged:);
    [rightPanel addSubview:_scalePopup];

    // Live Mic FFT Button
    _micButton = [NSButton buttonWithTitle:@"Enable Live Mic FFT" target:self action:@selector(onMicToggle:)];
    _micButton.bezelStyle = NSBezelStyleRounded;
    _micButton.frame = NSMakeRect(12, 46, 152, 26);
    [rightPanel addSubview:_micButton];

    _micStatusLabel = [self makeLabel:@"Touch Beat mode active" size:10.0 weight:NSFontWeightRegular
                                color:[NSColor colorWithWhite:0.65 alpha:1.0]];
    _micStatusLabel.frame = NSMakeRect(170, 51, colW - 182, 16);
    [rightPanel addSubview:_micStatusLabel];

    // Quick Fun & Handy Action Buttons Row
    NSButton *beatBtn = [NSButton buttonWithTitle:@"↻ New Beat" target:self action:@selector(onBeatRandClick:)];
    beatBtn.bezelStyle = NSBezelStyleRounded;
    beatBtn.frame = NSMakeRect(12, 11, 92, 26);
    [rightPanel addSubview:beatBtn];

    NSButton *turboBtn = [NSButton buttonWithTitle:@"★ Turbo" target:self action:@selector(onTurboClick:)];
    turboBtn.bezelStyle = NSBezelStyleRounded;
    turboBtn.frame = NSMakeRect(108, 11, 86, 26);
    [rightPanel addSubview:turboBtn];

    NSButton *snapBtn = [NSButton buttonWithTitle:@"📸 Snap" target:self action:@selector(onSnapClick:)];
    snapBtn.bezelStyle = NSBezelStyleRounded;
    snapBtn.frame = NSMakeRect(198, 11, 86, 26);
    [rightPanel addSubview:snapBtn];

    _awakeButton = [NSButton buttonWithTitle:@"☕ Awake" target:self action:@selector(onAwakeClick:)];
    _awakeButton.bezelStyle = NSBezelStyleRounded;
    _awakeButton.frame = NSMakeRect(288, 11, 98, 26);
    [rightPanel addSubview:_awakeButton];

  // Listen for live mic status changes
  [TPAudioEngine shared].onMicStateChanged =
      ^(BOOL active, NSString *statusText) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
          return;
        [strongSelf syncUI];
        if (statusText) {
          strongSelf->_micStatusLabel.stringValue = statusText;
        }
      };
}

- (void)syncUI {
  TPEngine *eng = [TPEngine shared];
  TPTouchBarController *tbc = [TPTouchBarController shared];
  TPAudioEngine *au = [TPAudioEngine shared];
  TPSystemMonitor *sys = [TPSystemMonitor shared];

  for (TPModeCardView *card in _modeCards) {
    card.selected = (card.mode == eng.mode);
    [card setNeedsDisplay:YES];
  }
  for (TPThemePillView *pill in _themePills) {
    pill.selected = (pill.theme == eng.theme);
    [pill setNeedsDisplay:YES];
  }

  _alwaysOnCheck.state =
      tbc.alwaysOnActive ? NSControlStateValueOn : NSControlStateValueOff;
  _fullWidthCheck.state =
      tbc.fullWidthMode ? NSControlStateValueOn : NSControlStateValueOff;
  _modePillCheck.state =
      eng.showModePill ? NSControlStateValueOn : NSControlStateValueOff;
  _mouseReactCheck.state =
      eng.mouseReactive ? NSControlStateValueOn : NSControlStateValueOff;
  _soundCheck.state =
      au.soundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  _volumeSlider.floatValue = au.masterVolume;
  _speedSlider.floatValue = eng.speedScale;
  [_scalePopup selectItemAtIndex:eng.synthScale];

  _micButton.title =
      au.micActive ? @"Disable Live Mic" : @"Enable Live Mic FFT";
  _awakeButton.title = sys.keepAwakeActive ? @"☕ Awake: ON" : @"☕ Keep Awake";

  if (tbc.alwaysOnActive) {
    _liveStatusPill.stringValue =
        tbc.fullWidthMode ? @"● FULL-WIDTH LIVE" : @"● ALWAYS-ON LIVE";
    _liveStatusPill.textColor = [NSColor colorWithRed:0.18
                                                green:0.98
                                                 blue:0.62
                                                alpha:1.0];
  } else {
    _liveStatusPill.stringValue = @"○ APP-ONLY MODE";
    _liveStatusPill.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
  }
}

- (void)showAndFocus {
  [self syncUI];
  [self showWindow:nil];
  [self.window makeKeyAndOrderFront:nil];
  [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
  if (_mirrorView) {
    [[TPEngine shared] registerDisplayView:_mirrorView];
  }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
  // Pause mirror redrawing when window is closed so Touch Bar runs lean in
  // background
  if (_mirrorView) {
    [[TPEngine shared] unregisterDisplayView:_mirrorView];
  }
}

#pragma mark - Control Callbacks

- (void)onAlwaysOnToggle:(NSButton *)sender {
  if (sender.state == NSControlStateValueOn) {
    [[TPTouchBarController shared] presentSystemTouchBar];
  } else {
    [[TPTouchBarController shared] dismissSystemTouchBar];
  }
  [self syncUI];
}

- (void)onFullWidthToggle:(NSButton *)sender {
  TPTouchBarController *tbc = [TPTouchBarController shared];
  tbc.fullWidthMode = (sender.state == NSControlStateValueOn);
  if (tbc.alwaysOnActive) {
    [tbc refreshPresentation];
  }
  [self syncUI];
}

- (void)onModePillToggle:(NSButton *)sender {
  [TPEngine shared].showModePill = (sender.state == NSControlStateValueOn);
}

- (void)onMouseReactToggle:(NSButton *)sender {
  [TPEngine shared].mouseReactive = (sender.state == NSControlStateValueOn);
}

- (void)onSpeedChanged:(NSSlider *)sender {
  [TPEngine shared].speedScale = sender.floatValue;
}

- (void)onSoundToggle:(NSButton *)sender {
  [TPAudioEngine shared].soundEnabled = (sender.state == NSControlStateValueOn);
}

- (void)onVolumeChanged:(NSSlider *)sender {
  [TPAudioEngine shared].masterVolume = sender.floatValue;
}

- (void)onScaleChanged:(NSPopUpButton *)sender {
  [TPEngine shared].synthScale = (TPSynthScale)sender.indexOfSelectedItem;
  [[TPEngine shared] showToast:TPSynthScaleName([TPEngine shared].synthScale)
                      subtitle:@"Synth Scale"];
}

- (void)onMicToggle:(NSButton *)sender {
  BOOL next = ![TPAudioEngine shared].micActive;
  if (next) {
    [TPEngine shared].mode = TPModeSpectrum;
  }
  [[TPAudioEngine shared] setMicEnabled:next];
  [self syncUI];
}

- (void)onBeatRandClick:(id)sender {
    [TPEngine shared].mode = TPModeBeatbox;
    [[TPEngine shared] randomizeBeatbox];
    [self syncUI];
}

- (void)onTurboClick:(id)sender {
  [TPEngine shared].mode = TPModePet;
  [[TPEngine shared] triggerPetTurbo];
  [self syncUI];
}

- (void)onSnapClick:(id)sender {
    [[TPSystemMonitor shared] takeClipboardScreenshot];
}

- (void)onAwakeClick:(id)sender {
  [[TPSystemMonitor shared] toggleKeepAwake];
  [self syncUI];
}

@end

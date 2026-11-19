#import "TPEngine.h"
#import "TPSystemMonitor.h"
#import <math.h>

@implementation TPEngine (ToolsMode)

- (void)togglePomodoro {
    if (_pomoRemaining <= 1.0) {
        _pomoRemaining = _pomoTotal;
    }
    _pomoRunning = !_pomoRunning;
    [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:_pomoRunning ? 1.25f : 0.85f];
    if (self.onStateChanged) self.onStateChanged();
}

- (void)resetPomodoro {
    _pomoRunning = NO;
    _pomoRemaining = _pomoTotal;
    [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:0.72f];
    [self showToast:@"POMODORO RESET" subtitle:@"25:00 Ready"];
    if (self.onStateChanged) self.onStateChanged();
}

- (void)stepTools:(float)dt {
    if (_pomoFlash > 0.0f) {
        _pomoFlash = MAX(0.0f, _pomoFlash - dt * 1.2f);
    }
    if (_hudTapFeedbackLife > 0.0f) {
        _hudTapFeedbackLife = MAX(0.0f, _hudTapFeedbackLife - dt * 3.2f);
    }

    // Kinetic inertia scroll & elastic edge rubber-band!
    if (!_hudIsDragging) {
        if (fabs(_hudScrollVel) > 1.0) {
            _hudScrollX += _hudScrollVel * dt;
            _hudScrollVel *= pow(0.035, dt);
        } else {
            _hudScrollVel = 0.0;
        }
        // Smooth spring-back if over-scrolled past left/right edge
        if (_hudScrollX < 0.0) {
            _hudScrollX *= pow(0.0005, dt);
            _hudScrollVel *= 0.6;
            if (fabs(_hudScrollX) < 0.3) _hudScrollX = 0.0;
        } else if (_hudScrollX > _hudMaxScroll) {
            CGFloat over = _hudScrollX - _hudMaxScroll;
            _hudScrollX = _hudMaxScroll + over * pow(0.0005, dt);
            _hudScrollVel *= 0.6;
            if (over < 0.3) _hudScrollX = _hudMaxScroll;
        }
    }

    if (_pomoRunning) {
        _pomoRemaining -= dt;
        if (_pomoRemaining <= 0.0) {
            _pomoRemaining = 0.0;
            _pomoRunning = NO;
            _pomoFlash = 1.0f;
            [[TPAudioEngine shared] playSFX:TPSFXPomodoroBell pan:0.0f pitchScale:1.0f];
            [self showToast:@"FOCUS COMPLETE!" subtitle:@"Take a well-earned break!"];
            for (int i = 0; i < 32; i++) {
                [self spawnParticleX:TPRandRange(0.1f, 0.9f)
                                   y:TPRandRange(4.0f, 26.0f)
                                  vx:TPRandRange(-0.15f, 0.15f)
                                  vy:TPRandRange(-20.0f, 35.0f)
                                life:TPRandRange(0.7f, 1.5f)
                                size:TPRandRange(3.5f, 6.5f)
                                 hue:TPRandf()
                                kind:0];
            }
            if (self.onStateChanged) self.onStateChanged();
        }
    }
}

#pragma mark - Kinetic Touch Sliding + Accurate Tap Actions

- (void)touchToolsBeganID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r {
    _hudActiveTouchID = tid;
    _hudIsDragging = YES;
    _hudDidSlide = NO;
    _hudDragStartX = pt.x;
    _hudLastDragX = pt.x;
    _hudDragStartScroll = _hudScrollX;
    _hudScrollVel = 0.0;
    _hudLastDragTime = CACurrentMediaTime();
}

- (void)touchToolsMovedID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r {
    if (!_hudIsDragging || tid != _hudActiveTouchID) return;

    CGFloat totalDelta = pt.x - _hudDragStartX;
    if (fabs(totalDelta) > 6.0) {
        _hudDidSlide = YES;
    }

    if (_hudDidSlide) {
        CGFloat rawScroll = _hudDragStartScroll - totalDelta;
        // Soft rubber-band resistance beyond edges
        if (rawScroll < 0.0) {
            rawScroll *= 0.35;
        } else if (rawScroll > _hudMaxScroll) {
            rawScroll = _hudMaxScroll + (rawScroll - _hudMaxScroll) * 0.35;
        }
        double now = CACurrentMediaTime();
        double dtMove = MAX(0.005, now - _hudLastDragTime);
        CGFloat instVel = -((pt.x - _hudLastDragX) / dtMove);
        _hudScrollVel = TPLerpf((float)_hudScrollVel, (float)TPClampf((float)instVel, -2400.0f, 2400.0f), 0.55f);
        _hudScrollX = rawScroll;
        _hudLastDragX = pt.x;
        _hudLastDragTime = now;
    }
}

- (void)touchToolsEndedID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r {
    if (tid != _hudActiveTouchID) return;
    _hudIsDragging = NO;

    // If user slid/flicked, let inertia glide naturally — don't fire a tap!
    if (_hudDidSlide) return;

    // Convert screen tap point into virtual deck coordinates
    CGPoint vpt = CGPointMake((pt.x - r.origin.x) + _hudScrollX, pt.y - r.origin.y);
    TPSystemMonitor *sys = [TPSystemMonitor shared];
    float normTapX = TPClampf((float)((pt.x - r.origin.x) / MAX(1.0, r.size.width)), 0.0f, 1.0f);
    _hudTapFeedbackX = normTapX;
    _hudTapFeedbackLife = 1.0f;

    // 1. Media Controls
    if (CGRectContainsPoint(_hitMediaPrev, vpt)) {
        [sys mediaPrevious];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:-0.5f pitchScale:0.9f];
        [self showToast:@"⏮ PREVIOUS TRACK" subtitle:sys.nowPlayingApp.length ? sys.nowPlayingApp : @"Media"];
        return;
    }
    if (CGRectContainsPoint(_hitMediaPlay, vpt)) {
        [sys mediaPlayPause];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:-0.3f pitchScale:1.2f];
        [self showToast:(sys.nowPlayingIsPlaying ? @"▶ PLAYING" : @"❚❚ PAUSED") subtitle:sys.nowPlayingTrack];
        return;
    }
    if (CGRectContainsPoint(_hitMediaNext, vpt)) {
        [sys mediaNext];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:-0.1f pitchScale:1.15f];
        [self showToast:@"⏭ NEXT TRACK" subtitle:sys.nowPlayingApp.length ? sys.nowPlayingApp : @"Media"];
        return;
    }

    // 2. Native System Mute & Volume Scrub Bar
    if (CGRectContainsPoint(_hitMuteBtn, vpt)) {
        [sys toggleSystemMute];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:sys.systemMuted ? 0.65f : 1.3f];
        [self showToast:(sys.systemMuted ? @"🔇 AUDIO MUTED" : @"🔊 AUDIO UNMUTED") subtitle:@"System Output"];
        if (self.onStateChanged) self.onStateChanged();
        return;
    }
    if (CGRectContainsPoint(_hitVolBar, vpt)) {
        float frac = TPClampf((float)((vpt.x - _hitVolBar.origin.x) / MAX(1.0, _hitVolBar.size.width)), 0.0f, 1.0f);
        [sys setSystemVolume:frac];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:0.75f + frac * 0.8f];
        return;
    }

    // 3. Everyday Quick Actions (Screenshot, Keep Awake, Lock Screen)
    if (CGRectContainsPoint(_hitSnapBtn, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.1f pitchScale:1.45f];
        [self showToast:@"📸 CLIPBOARD SNAP" subtitle:@"Drag area to copy screenshot"];
        [sys takeClipboardScreenshot];
        return;
    }
    if (CGRectContainsPoint(_hitAwakeBtn, vpt)) {
        [sys toggleKeepAwake];
        BOOL awake = sys.keepAwakeActive;
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.2f pitchScale:awake ? 1.35f : 0.78f];
        [self showToast:(awake ? @"☕ KEEP AWAKE ON" : @"☾ KEEP AWAKE OFF")
               subtitle:(awake ? @"Display sleep prevented" : @"Normal sleep restored")];
        if (self.onStateChanged) self.onStateChanged();
        return;
    }
    if (CGRectContainsPoint(_hitLockBtn, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.3f pitchScale:0.7f];
        [sys lockScreenNow];
        return;
    }

    // 4. Pomodoro Focus Timer
    if (CGRectContainsPoint(_hitPomoBtn, vpt)) {
        double now = CACurrentMediaTime();
        if (now - _lastPomoTap < 0.34) {
            [self resetPomodoro];
            _lastPomoTap = 0.0;
        } else {
            _lastPomoTap = now;
            [self togglePomodoro];
        }
        return;
    }

    // 5. Quick App Launchers
    if (CGRectContainsPoint(_hitAppTerm, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.5f pitchScale:1.25f];
        [self showToast:@">_ TERMINAL" subtitle:@"Launching Terminal"];
        [sys launchAppWithBundleID:@"com.apple.Terminal" fallbackPath:@"/System/Applications/Utilities/Terminal.app"];
        return;
    }
    if (CGRectContainsPoint(_hitAppFinder, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.5f pitchScale:1.25f];
        [self showToast:@"⊞ FINDER" subtitle:@"Switching to Finder"];
        [sys launchAppWithBundleID:@"com.apple.finder" fallbackPath:@"/System/Library/CoreServices/Finder.app"];
        return;
    }
    if (CGRectContainsPoint(_hitAppBrowser, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.5f pitchScale:1.25f];
        [self showToast:@"◎ BROWSER" subtitle:@"Opening Browser"];
        NSURL *chrome = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.google.Chrome"];
        [sys launchAppWithBundleID:(chrome ? @"com.google.Chrome" : @"com.apple.Safari")
                      fallbackPath:@"/Applications/Safari.app"];
        return;
    }
    if (CGRectContainsPoint(_hitAppNotes, vpt)) {
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.5f pitchScale:1.25f];
        [self showToast:@"✎ NOTES" subtitle:@"Opening Notes"];
        [sys launchAppWithBundleID:@"com.apple.Notes" fallbackPath:@"/System/Applications/Notes.app"];
        return;
    }

    // Gentle neon tap burst elsewhere
    for (int i = 0; i < 6; i++) {
        [self spawnParticleX:normTapX y:pt.y vx:TPRandRange(-0.06f, 0.06f) vy:TPRandRange(-16.0f, 16.0f)
                        life:0.32f size:3.0f hue:normTapX kind:0];
    }
}

#pragma mark - Card Helpers & Scrollable Deck Renderer

static void TPDrawDeckCard(CGContextRef ctx, CGRect rect, TPRGBA accent, BOOL highlight) {
    TPDrawRoundedRect(ctx, rect, 6.0);
    if (highlight) {
        CGContextSetRGBFillColor(ctx, accent.r * 0.28 + 0.04, accent.g * 0.28 + 0.04, accent.b * 0.28 + 0.06, 0.95);
    } else {
        CGContextSetRGBFillColor(ctx, 0.085, 0.095, 0.135, 0.96);
    }
    CGContextFillPath(ctx);

    TPDrawRoundedRect(ctx, CGRectInset(rect, 0.5, 0.5), 5.5);
    CGContextSetRGBStrokeColor(ctx, accent.r, accent.g, accent.b, highlight ? 0.95 : 0.42);
    CGContextSetLineWidth(ctx, highlight ? 1.25 : 0.9);
    CGContextStrokePath(ctx);
}

static void TPDrawMiniActionBtn(CGContextRef ctx, CGRect rect, NSString *label, TPRGBA col, BOOL active) {
    TPDrawDeckCard(ctx, rect, col, active);
    CGSize sz = TPMeasureText(label, 9.5, NSFontWeightBold, NO);
    TPDrawText(ctx, label,
               CGPointMake(rect.origin.x + (rect.size.width - sz.width) * 0.5,
                           rect.origin.y + (rect.size.height - sz.height) * 0.5),
               9.5, NSFontWeightBold,
               active ? [NSColor whiteColor] : [NSColor colorWithRed:TPLerpf(col.r, 1.0f, 0.45f)
                                                               green:TPLerpf(col.g, 1.0f, 0.45f)
                                                                blue:TPLerpf(col.b, 1.0f, 0.45f) alpha:1.0],
               NO);
}

- (void)renderTools:(CGContextRef)ctx rect:(CGRect)r {
    TPSystemMonitor *sys = [TPSystemMonitor shared];
    CGFloat h = r.size.height;
    CGFloat cardH = h - 6.0;
    CGFloat cardY = 3.5;
    CGFloat gap = 6.0;

    // Apply horizontal kinetic scroll translation inside the clipped canvas
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, r.origin.x - _hudScrollX, r.origin.y);

    CGFloat vx = 6.0; // virtual X cursor across the entire scrollable deck!

    // ---------------------------------------------------------
    // 1. LIVE NOW PLAYING + MEDIA CONTROLS (228pt)
    // ---------------------------------------------------------
    CGRect mediaR = CGRectMake(vx, cardY, 228.0, cardH);
    TPRGBA mediaCol = sys.nowPlayingIsPlaying ? (TPRGBA){0.18f, 0.95f, 0.52f, 1.0f} : TPThemeColor(_theme, 0.12f, 1.0f);
    TPDrawDeckCard(ctx, mediaR, mediaCol, sys.nowPlayingIsPlaying);

    _hitMediaPrev = CGRectMake(vx + 4.0,  cardY, 24.0, cardH);
    _hitMediaPlay = CGRectMake(vx + 28.0, cardY, 28.0, cardH);
    _hitMediaNext = CGRectMake(vx + 56.0, cardY, 24.0, cardH);

    TPDrawText(ctx, @"⏮", CGPointMake(vx + 9.0,  cardY + 5.5), 10.5, NSFontWeightBold, [NSColor colorWithWhite:0.85 alpha:1.0], NO);
    TPDrawText(ctx, sys.nowPlayingIsPlaying ? @"❚❚" : @"▶",
               CGPointMake(vx + 36.0, cardY + 6.0), 10.0, NSFontWeightBold,
               [NSColor colorWithRed:mediaCol.r green:mediaCol.g blue:mediaCol.b alpha:1.0], NO);
    TPDrawText(ctx, @"⏭", CGPointMake(vx + 61.0, cardY + 5.5), 10.5, NSFontWeightBold, [NSColor colorWithWhite:0.85 alpha:1.0], NO);

    // Track info (or friendly ready hint) clipped neatly inside media card
    NSString *trackStr = sys.nowPlayingTrack.length > 0
        ? (sys.nowPlayingArtist.length > 0 ? [NSString stringWithFormat:@"%@ — %@", sys.nowPlayingTrack, sys.nowPlayingArtist] : sys.nowPlayingTrack)
        : @"Spotify / Music Ready";
    CGContextSaveGState(ctx);
    CGRect txtClip = CGRectMake(vx + 84.0, cardY + 2.0, 138.0, cardH - 4.0);
    CGContextClipToRect(ctx, txtClip);
    CGSize tsz = TPMeasureText(trackStr, 9.5, NSFontWeightSemibold, NO);
    CGFloat scrollOff = 0.0;
    if (tsz.width > txtClip.size.width) {
        double cycle = fmod(_time * 26.0, tsz.width + 36.0);
        scrollOff = (CGFloat)cycle;
    }
    TPDrawText(ctx, trackStr, CGPointMake(txtClip.origin.x - scrollOff, cardY + 6.0),
               9.5, NSFontWeightSemibold, [NSColor colorWithWhite:0.95 alpha:0.95], NO);
    if (scrollOff > 0.0) {
        TPDrawText(ctx, trackStr, CGPointMake(txtClip.origin.x - scrollOff + tsz.width + 36.0, cardY + 6.0),
                   9.5, NSFontWeightSemibold, [NSColor colorWithWhite:0.95 alpha:0.95], NO);
    }
    CGContextRestoreGState(ctx);
    vx += 228.0 + gap;

    // ---------------------------------------------------------
    // 2. NATIVE SYSTEM VOLUME SCRUB + ONE-TAP MUTE (168pt)
    // ---------------------------------------------------------
    CGRect volCard = CGRectMake(vx, cardY, 168.0, cardH);
    TPRGBA volCol = sys.systemMuted ? (TPRGBA){1.0f, 0.25f, 0.35f, 1.0f} : TPThemeColor(_theme, 0.45f, 1.0f);
    TPDrawDeckCard(ctx, volCard, volCol, sys.systemMuted);

    _hitMuteBtn = CGRectMake(vx + 2.0, cardY, 32.0, cardH);
    NSString *spk = sys.systemMuted ? @"🔇" : (sys.systemVolume > 0.5f ? @"🔊" : @"🔉");
    TPDrawText(ctx, spk, CGPointMake(vx + 9.0, cardY + 5.0), 11.5, NSFontWeightBold, [NSColor whiteColor], NO);

    _hitVolBar = CGRectMake(vx + 36.0, cardY + 3.0, 124.0, cardH - 6.0);
    TPDrawRoundedRect(ctx, _hitVolBar, 4.5);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.12);
    CGContextFillPath(ctx);

    float dispVol = sys.systemMuted ? 0.0f : sys.systemVolume;
    if (dispVol > 0.01f) {
        CGRect vFill = CGRectMake(_hitVolBar.origin.x, _hitVolBar.origin.y, _hitVolBar.size.width * dispVol, _hitVolBar.size.height);
        TPDrawRoundedRect(ctx, vFill, 4.5);
        CGContextSetRGBFillColor(ctx, volCol.r, volCol.g, volCol.b, 0.72);
        CGContextFillPath(ctx);
    }
    NSString *vTxt = sys.systemMuted ? @"MUTED" : [NSString stringWithFormat:@"VOL %d%%", (int)lroundf(sys.systemVolume * 100.0f)];
    CGSize vs = TPMeasureText(vTxt, 9.0, NSFontWeightBold, YES);
    TPDrawText(ctx, vTxt,
               CGPointMake(_hitVolBar.origin.x + (_hitVolBar.size.width - vs.width) * 0.5,
                           _hitVolBar.origin.y + (_hitVolBar.size.height - vs.height) * 0.5),
               9.0, NSFontWeightBold, [NSColor whiteColor], YES);
    vx += 168.0 + gap;

    // ---------------------------------------------------------
    // 3. HANDY QUICK ACTIONS: SNAPSHOT / KEEP AWAKE / LOCK (186pt)
    // ---------------------------------------------------------
    _hitSnapBtn = CGRectMake(vx, cardY, 60.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitSnapBtn, @"📸 SNAP", (TPRGBA){0.15f, 0.85f, 1.0f, 1.0f}, NO);
    vx += 60.0 + 4.0;

    _hitAwakeBtn = CGRectMake(vx, cardY, 66.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitAwakeBtn, sys.keepAwakeActive ? @"☕ ON" : @"☕ AWAKE",
                        (TPRGBA){1.0f, 0.78f, 0.18f, 1.0f}, sys.keepAwakeActive);
    vx += 66.0 + 4.0;

    _hitLockBtn = CGRectMake(vx, cardY, 56.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitLockBtn, @"🔒 LOCK", (TPRGBA){1.0f, 0.35f, 0.55f, 1.0f}, NO);
    vx += 56.0 + gap;

    // ---------------------------------------------------------
    // 4. INTERACTIVE POMODORO FOCUS TIMER (116pt)
    // ---------------------------------------------------------
    _hitPomoBtn = CGRectMake(vx, cardY, 116.0, cardH);
    TPRGBA pomoCol = _pomoRunning ? (TPRGBA){1.0f, 0.42f, 0.24f, 1.0f} : (TPRGBA){0.45f, 0.72f, 1.0f, 1.0f};
    TPDrawDeckCard(ctx, _hitPomoBtn, pomoCol, _pomoRunning);
    int remSec = (int)ceil(_pomoRemaining);
    NSString *pomoStr = [NSString stringWithFormat:@"%@ %02d:%02d", _pomoRunning ? @"▶" : @"◉", remSec / 60, remSec % 60];
    CGSize ps = TPMeasureText(pomoStr, 10.0, NSFontWeightBold, YES);
    TPDrawText(ctx, pomoStr,
               CGPointMake(_hitPomoBtn.origin.x + (_hitPomoBtn.size.width - ps.width) * 0.5, cardY + 8.0),
               10.0, NSFontWeightBold, [NSColor whiteColor], YES);

    float pomoProg = 1.0f - TPClampf((float)(_pomoRemaining / MAX(1.0, _pomoTotal)), 0.0f, 1.0f);
    CGRect pTrack = CGRectMake(_hitPomoBtn.origin.x + 8.0, cardY + 3.0, _hitPomoBtn.size.width - 16.0, 3.0);
    TPDrawRoundedRect(ctx, pTrack, 1.5);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.14);
    CGContextFillPath(ctx);
    if (pomoProg > 0.005f) {
        TPDrawRoundedRect(ctx, CGRectMake(pTrack.origin.x, pTrack.origin.y, pTrack.size.width * pomoProg, 3.0), 1.5);
        CGContextSetRGBFillColor(ctx, pomoCol.r, pomoCol.g, pomoCol.b, 0.96);
        CGContextFillPath(ctx);
    }
    vx += 116.0 + gap;

    // ---------------------------------------------------------
    // 5. LIVE CPU + PER-CORE EQUALIZER + SPARKLINE (188pt)
    // ---------------------------------------------------------
    CGRect cpuR = CGRectMake(vx, cardY, 188.0, cardH);
    float cpu = sys.cpuUsage;
    TPRGBA cpuCol = (cpu > 0.75f) ? (TPRGBA){1.0f, 0.24f, 0.30f, 1.0f}
                  : (cpu > 0.45f) ? (TPRGBA){1.0f, 0.72f, 0.16f, 1.0f}
                  : TPThemeColor(_theme, 0.05f, 1.0f);
    TPDrawDeckCard(ctx, cpuR, cpuCol, NO);
    TPDrawText(ctx, [NSString stringWithFormat:@"CPU %2.0f%%", cpu * 100.0f],
               CGPointMake(vx + 7.0, cardY + 6.5), 10.0, NSFontWeightBold,
               [NSColor colorWithRed:cpuCol.r green:cpuCol.g blue:cpuCol.b alpha:1.0], YES);

    // Individual live core bars (shows every CPU thread dancing!)
    int nCores = MIN(16, MAX(1, sys.cpuCoreCount));
    float cores[TP_MAX_CPU_CORES];
    [sys copyPerCoreCPU:cores maxCount:TP_MAX_CPU_CORES];
    CGFloat barStartX = vx + 66.0;
    CGFloat barAreaW = 54.0;
    CGFloat cw = MAX(2.0, (barAreaW / (CGFloat)nCores) - 1.0);
    for (int c = 0; c < nCores; c++) {
        CGFloat bh = MAX(2.0, cores[c] * (cardH - 7.0));
        CGContextSetRGBFillColor(ctx, cpuCol.r, cpuCol.g, cpuCol.b, 0.35 + 0.65 * cores[c]);
        CGContextFillRect(ctx, CGRectMake(barStartX + c * (cw + 1.0), cardY + 3.5, cw, bh));
    }

    // Mini sparkline on right side of CPU card
    float hist[TP_CPU_HISTORY_COUNT];
    [sys copyCPUHistory:hist count:TP_CPU_HISTORY_COUNT];
    CGFloat gX = vx + 126.0;
    CGFloat gW = 55.0;
    CGContextBeginPath(ctx);
    for (int i = 0; i < TP_CPU_HISTORY_COUNT; i++) {
        CGFloat px = gX + ((CGFloat)i / (CGFloat)(TP_CPU_HISTORY_COUNT - 1)) * gW;
        CGFloat py = cardY + 3.5 + hist[i] * (cardH - 7.0);
        if (i == 0) CGContextMoveToPoint(ctx, px, py);
        else CGContextAddLineToPoint(ctx, px, py);
    }
    CGContextSetRGBStrokeColor(ctx, cpuCol.r, cpuCol.g, cpuCol.b, 0.92);
    CGContextSetLineWidth(ctx, 1.3);
    CGContextStrokePath(ctx);
    vx += 188.0 + gap;

    // ---------------------------------------------------------
    // 6. RAM BREAKDOWN (138pt)
    // ---------------------------------------------------------
    CGRect ramR = CGRectMake(vx, cardY, 138.0, cardH);
    TPRGBA ramCol = TPThemeColor(_theme, 0.35f, 1.0f);
    TPDrawDeckCard(ctx, ramR, ramCol, NO);
    TPDrawText(ctx, [NSString stringWithFormat:@"RAM %.1f / %.0fG", sys.ramUsedGB, sys.ramTotalGB],
               CGPointMake(vx + 8.0, cardY + 8.0), 9.5, NSFontWeightBold, [NSColor whiteColor], YES);
    CGRect rTrk = CGRectMake(vx + 8.0, cardY + 3.0, 122.0, 3.0);
    TPDrawRoundedRect(ctx, rTrk, 1.5);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.14);
    CGContextFillPath(ctx);
    TPDrawRoundedRect(ctx, CGRectMake(rTrk.origin.x, rTrk.origin.y, rTrk.size.width * sys.ramUsage, 3.0), 1.5);
    CGContextSetRGBFillColor(ctx, ramCol.r, ramCol.g, ramCol.b, 0.95);
    CGContextFillPath(ctx);
    vx += 138.0 + gap;

    // ---------------------------------------------------------
    // 7. SSD DISK SPACE (128pt)
    // ---------------------------------------------------------
    CGRect ssdR = CGRectMake(vx, cardY, 128.0, cardH);
    TPRGBA ssdCol = TPThemeColor(_theme, 0.60f, 1.0f);
    TPDrawDeckCard(ctx, ssdR, ssdCol, NO);
    TPDrawText(ctx, [NSString stringWithFormat:@"SSD %.0fG FREE", sys.diskFreeGB],
               CGPointMake(vx + 8.0, cardY + 8.0), 9.5, NSFontWeightBold, [NSColor whiteColor], YES);
    float diskUsedFrac = sys.diskTotalGB > 1.0f ? TPClampf(1.0f - (sys.diskFreeGB / sys.diskTotalGB), 0.0f, 1.0f) : 0.5f;
    CGRect dTrk = CGRectMake(vx + 8.0, cardY + 3.0, 112.0, 3.0);
    TPDrawRoundedRect(ctx, dTrk, 1.5);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.14);
    CGContextFillPath(ctx);
    TPDrawRoundedRect(ctx, CGRectMake(dTrk.origin.x, dTrk.origin.y, dTrk.size.width * diskUsedFrac, 3.0), 1.5);
    CGContextSetRGBFillColor(ctx, ssdCol.r, ssdCol.g, ssdCol.b, 0.95);
    CGContextFillPath(ctx);
    vx += 128.0 + gap;

    // ---------------------------------------------------------
    // 8. FULL-WIDTH NETWORK SPEED (164pt — zero clipping!)
    // ---------------------------------------------------------
    CGRect netR = CGRectMake(vx, cardY, 164.0, cardH);
    TPRGBA netCol = TPThemeColor(_theme, 0.72f, 1.0f);
    TPDrawDeckCard(ctx, netR, netCol, NO);
    NSString *netStr = [NSString stringWithFormat:@"↓ %@/s  ↑ %@/s",
                        [sys formattedRate:sys.netDownBytesPerSec],
                        [sys formattedRate:sys.netUpBytesPerSec]];
    CGSize ns = TPMeasureText(netStr, 9.5, NSFontWeightSemibold, YES);
    TPDrawText(ctx, netStr,
               CGPointMake(netR.origin.x + (netR.size.width - ns.width) * 0.5, cardY + 6.0),
               9.5, NSFontWeightSemibold, [NSColor colorWithRed:0.78 green:0.96 blue:1.0 alpha:0.98], YES);
    vx += 164.0 + gap;

    // ---------------------------------------------------------
    // 9. DETAILED BATTERY + TIME REMAINING (140pt)
    // ---------------------------------------------------------
    CGRect batR = CGRectMake(vx, cardY, 140.0, cardH);
    int pct = sys.batteryPercent;
    TPRGBA batCol = sys.batteryCharging ? (TPRGBA){0.20f, 0.98f, 0.48f, 1.0f}
                  : (pct <= 20)         ? (TPRGBA){1.00f, 0.24f, 0.28f, 1.0f}
                  :                       (TPRGBA){0.35f, 0.92f, 0.62f, 1.0f};
    TPDrawDeckCard(ctx, batR, batCol, (pct <= 15 && sinf((float)_time * 5.0f) > 0));
    NSString *batStr;
    if (sys.batteryMinutesLeft > 0) {
        int bh = sys.batteryMinutesLeft / 60;
        int bm = sys.batteryMinutesLeft % 60;
        batStr = [NSString stringWithFormat:@"%@%d%% • %dh%02dm", sys.batteryCharging ? @"⚡" : @"", pct, bh, bm];
    } else {
        batStr = [NSString stringWithFormat:@"%@%d%% %@", sys.batteryCharging ? @"⚡" : @"BAT ", pct,
                  sys.batteryCharging ? @"CHG" : (sys.batteryPluggedIn ? @"AC" : @"")];
    }
    CGSize bs = TPMeasureText(batStr, 9.5, NSFontWeightBold, YES);
    TPDrawText(ctx, batStr, CGPointMake(batR.origin.x + (batR.size.width - bs.width) * 0.5, cardY + 8.0),
               9.5, NSFontWeightBold, [NSColor colorWithRed:batCol.r green:batCol.g blue:batCol.b alpha:1.0], YES);
    CGRect bTrk = CGRectMake(vx + 8.0, cardY + 3.0, 124.0, 3.0);
    TPDrawRoundedRect(ctx, bTrk, 1.5);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.14);
    CGContextFillPath(ctx);
    TPDrawRoundedRect(ctx, CGRectMake(bTrk.origin.x, bTrk.origin.y, bTrk.size.width * TPClampf((float)pct / 100.0f, 0.0f, 1.0f), 3.0), 1.5);
    CGContextSetRGBFillColor(ctx, batCol.r, batCol.g, batCol.b, 0.96);
    CGContextFillPath(ctx);
    vx += 140.0 + gap;

    // ---------------------------------------------------------
    // 10. QUICK APP LAUNCHER DECK (224pt)
    // ---------------------------------------------------------
    _hitAppTerm    = CGRectMake(vx, cardY, 54.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitAppTerm, @">_ Term", TPThemeColor(_theme, 0.05f, 1.0f), NO);
    vx += 58.0;

    _hitAppFinder  = CGRectMake(vx, cardY, 54.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitAppFinder, @"⊞ Find", TPThemeColor(_theme, 0.30f, 1.0f), NO);
    vx += 58.0;

    _hitAppBrowser = CGRectMake(vx, cardY, 54.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitAppBrowser, @"◎ Web", TPThemeColor(_theme, 0.55f, 1.0f), NO);
    vx += 58.0;

    _hitAppNotes   = CGRectMake(vx, cardY, 54.0, cardH);
    TPDrawMiniActionBtn(ctx, _hitAppNotes, @"✎ Note", TPThemeColor(_theme, 0.80f, 1.0f), NO);
    vx += 54.0 + gap;

    // ---------------------------------------------------------
    // 11. LIVE CLOCK + DATE (148pt)
    // ---------------------------------------------------------
    CGRect clkR = CGRectMake(vx, cardY, 148.0, cardH);
    TPRGBA clkCol = TPThemeColor(_theme, 0.88f, 1.0f);
    TPDrawDeckCard(ctx, clkR, clkCol, NO);
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss  E d";
    });
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    CGSize ts = TPMeasureText(timeStr, 9.5, NSFontWeightBold, YES);
    TPDrawText(ctx, timeStr,
               CGPointMake(clkR.origin.x + (clkR.size.width - ts.width) * 0.5, cardY + 6.0),
               9.5, NSFontWeightBold, [NSColor whiteColor], YES);
    vx += 148.0 + 10.0;

    CGContextRestoreGState(ctx);

    // Update max scroll bounds dynamically for whatever Touch Bar width is active!
    _hudMaxScroll = MAX(0.0, vx - r.size.width);

    // ---------------------------------------------------------
    // SCROLL AFFORDANCE: Subtle Bottom Neon Scrollbar + Edge Chevrons!
    // ---------------------------------------------------------
    if (_hudMaxScroll > 4.0) {
        CGFloat trackW = r.size.width - 16.0;
        CGFloat thumbW = MAX(32.0, trackW * (r.size.width / vx));
        CGFloat scrollFrac = TPClampf((float)(_hudScrollX / _hudMaxScroll), 0.0f, 1.0f);
        CGFloat thumbX = r.origin.x + 8.0 + (trackW - thumbW) * scrollFrac;

        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.10);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + 8.0, r.origin.y + 0.6, trackW, 1.6));

        TPRGBA scCol = TPThemeColor(_theme, scrollFrac, (_hudIsDragging || fabs(_hudScrollVel) > 5.0) ? 0.95f : 0.62f);
        CGContextSetRGBFillColor(ctx, scCol.r, scCol.g, scCol.b, scCol.a);
        CGContextFillRect(ctx, CGRectMake(thumbX, r.origin.y + 0.5, thumbW, 2.0));

        // Glowing '<' / '>' edge scroll hints whenever more cards sit off-screen!
        if (_hudScrollX > 8.0) {
            CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.72);
            CGContextFillRect(ctx, CGRectMake(r.origin.x, r.origin.y, 16.0, h));
            TPDrawText(ctx, @"‹", CGPointMake(r.origin.x + 4.0, r.origin.y + 5.5), 14.0, NSFontWeightHeavy,
                       TPThemeNSColor(_theme, 0.05f, 0.95f), NO);
        }
        if (_hudScrollX < _hudMaxScroll - 8.0) {
            CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.72);
            CGContextFillRect(ctx, CGRectMake(r.origin.x + r.size.width - 16.0, r.origin.y, 16.0, h));
            TPDrawText(ctx, @"›", CGPointMake(r.origin.x + r.size.width - 11.0, r.origin.y + 5.5), 14.0, NSFontWeightHeavy,
                       TPThemeNSColor(_theme, 0.65f, 0.95f), NO);
        }
    }

    // Subtle tap flash & Pomodoro complete rainbow flash
    if (_pomoFlash > 0.01f) {
        TPRGBA fc = TPThemeColor(_theme, fmodf((float)_time * 1.5f, 1.0f), _pomoFlash * 0.35f);
        CGContextSetRGBFillColor(ctx, fc.r, fc.g, fc.b, fc.a);
        CGContextFillRect(ctx, r);
    }
}

@end

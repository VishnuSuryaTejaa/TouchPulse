#import "TPEngine.h"
#import "TPSystemMonitor.h"
#import <math.h>

@interface TPEngine () {
    NSTimer *_frameTimer;
    double _lastFrameTime;
    uint64_t _frameCount;
    NSHashTable<NSView *> *_displayViews;
    double _lastThreeFingerSwitch;
}
@end

@implementation TPEngine

+ (instancetype)shared {
    static TPEngine *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[TPEngine alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _displayViews = [NSHashTable weakObjectsHashTable];
        _mode = TPModePlasma;
        _theme = TPThemeCyberpunk;
        _synthScale = TPSynthScalePentatonic;
        _speedScale = 1.0f;
        _showModePill = YES;
        _mouseReactive = YES;
        _lastFrameTime = CACurrentMediaTime();

        _runnerHighScore = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"TouchPulseRunnerHigh"];
        _blasterHighScore = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"TouchPulseBlasterHigh"];

        _pomoTotal = 25.0 * 60.0;
        _pomoRemaining = _pomoTotal;
        _pomoRunning = NO;

        [self initVisualModes];
        [self initChaosModes];
        [self resetRunner];
        [self resetBlaster];
        [self showToast:TPModeName(_mode) subtitle:@"Touch, slide & flick across the bar!"];
    }
    return self;
}

- (void)dealloc {
    [_frameTimer invalidate];
}

- (BOOL)isRunning {
    return _frameTimer != nil;
}

- (void)registerDisplayView:(NSView *)view {
    if (!view) return;
    [_displayViews addObject:view];
    [self updateRunningState];
}

- (void)unregisterDisplayView:(NSView *)view {
    if (!view) return;
    [_displayViews removeObject:view];
    [self updateRunningState];
}

- (void)updateRunningState {
    BOOL anyView = NO;
    for (NSView *v in _displayViews) {
        if (v && !v.hidden) {
            anyView = YES;
            break;
        }
    }
    if (anyView && !_frameTimer) {
        _lastFrameTime = CACurrentMediaTime();
        __weak typeof(self) weakSelf = self;
        // 45 FPS: silky smooth on OLED Touch Bar while cutting CoreGraphics CPU usage dramatically
        _frameTimer = [NSTimer timerWithTimeInterval:(1.0 / 45.0) repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf tick];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_frameTimer forMode:NSRunLoopCommonModes];
    } else if (!anyView && _frameTimer) {
        [_frameTimer invalidate];
        _frameTimer = nil;
        [[TPAudioEngine shared] setDroneLevel:0.0f freq:55.0f pan:0.0f];
    }
}

- (void)setMode:(TPMode)mode {
    if (mode < 0 || mode >= TPModeCount) return;
    if (_mode == mode) return;
    _mode = mode;
    _modeFlash = 1.0f;
    [self clearParticles];
    [self cancelAllTouches];
    [[TPAudioEngine shared] setDroneLevel:0.0f freq:55.0f pan:0.0f];
    [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:1.0f + 0.08f * (float)mode];

    if (_mode == TPModeRunner && _runnerGameOver) {
        [self resetRunner];
    } else if (_mode == TPModeBlaster && _blasterGameOver) {
        [self resetBlaster];
    }

    [self showToast:TPModeName(_mode) subtitle:TPModeSubtitle(_mode)];
    if (self.onStateChanged) self.onStateChanged();
}

- (void)setTheme:(TPTheme)theme {
    if (theme < 0 || theme >= TPThemeCount) return;
    _theme = theme;
    _modeFlash = 0.65f;
    [self showToast:TPThemeName(theme) subtitle:@"Color Palette"];
    if (self.onStateChanged) self.onStateChanged();
}

- (void)cycleNextMode {
    [self setMode:(TPMode)((_mode + 1) % TPModeCount)];
}

- (void)cyclePrevMode {
    [self setMode:(TPMode)((_mode + TPModeCount - 1) % TPModeCount)];
}

- (void)cycleNextTheme {
    [self setTheme:(TPTheme)((_theme + 1) % TPThemeCount)];
}

- (void)showToast:(NSString *)title subtitle:(NSString *)sub {
    _hudTitle = title;
    _hudSub = sub;
    _hudUntil = CACurrentMediaTime() + 1.55;
}

#pragma mark - Particles

- (void)clearParticles {
    memset(_particles, 0, sizeof(_particles));
}

- (void)spawnParticleX:(float)normX y:(float)py vx:(float)vx vy:(float)vy
                  life:(float)life size:(float)size hue:(float)hue kind:(int)kind {
    int slot = -1;
    float minLife = 999.0f;
    for (int i = 0; i < TP_MAX_PARTICLES; i++) {
        if (!_particles[i].active) {
            slot = i;
            break;
        }
        if (_particles[i].life < minLife) {
            minLife = _particles[i].life;
            slot = i;
        }
    }
    if (slot < 0) return;
    TPParticle *p = &_particles[slot];
    p->active = YES;
    p->x = normX;
    p->y = py;
    p->vx = vx;
    p->vy = vy;
    p->life = life;
    p->maxLife = life;
    p->size = size;
    p->hue = hue;
    p->kind = kind;
}

- (void)stepParticles:(float)dt {
    for (int i = 0; i < TP_MAX_PARTICLES; i++) {
        TPParticle *p = &_particles[i];
        if (!p->active) continue;
        p->life -= dt;
        if (p->life <= 0.0f) {
            p->active = NO;
            continue;
        }
        p->x += p->vx * dt;
        p->y += p->vy * dt;
        if (p->kind == 0 || p->kind == 1) {
            p->vx *= (1.0f - TPClampf(dt * 2.2f, 0.0f, 0.5f));
            p->vy *= (1.0f - TPClampf(dt * 1.4f, 0.0f, 0.5f));
        } else if (p->kind == 2) {
            // Floating heart gently sways upward
            p->x += sinf((float)_time * 5.0f + p->hue * 12.0f) * 0.015f * dt;
        } else if (p->kind == 3) {
            // Arcade shatter pixel with gravity
            p->vy -= 65.0f * dt;
        }
    }
}

- (void)renderParticles:(CGContextRef)ctx rect:(CGRect)r {
    for (int i = 0; i < TP_MAX_PARTICLES; i++) {
        TPParticle *p = &_particles[i];
        if (!p->active) continue;
        float t = TPClampf(p->life / MAX(0.001f, p->maxLife), 0.0f, 1.0f);
        CGFloat cx = r.origin.x + p->x * r.size.width;
        CGFloat cy = r.origin.y + p->y;
        TPRGBA col = TPThemeColor(_theme, p->hue, t);

        if (p->kind == 0) {
            TPDrawGlowCircle(ctx, cx, cy, p->size * (0.45f + 0.55f * t), col);
        } else if (p->kind == 1) {
            CGContextSetRGBStrokeColor(ctx, col.r, col.g, col.b, t);
            CGContextSetLineWidth(ctx, MAX(1.0f, p->size * 0.45f));
            CGContextMoveToPoint(ctx, cx, cy);
            CGContextAddLineToPoint(ctx, cx - p->vx * r.size.width * 0.045f, cy - p->vy * 0.045f);
            CGContextStrokePath(ctx);
        } else if (p->kind == 2) {
            // Crisp neon heart
            NSColor *hc = [NSColor colorWithRed:1.0 green:0.28 blue:0.62 alpha:t];
            TPDrawText(ctx, @"♥", CGPointMake(cx - 4.0, cy - 5.0), 9.0 + 2.0 * (1.0 - t), NSFontWeightBold, hc, NO);
        } else {
            CGContextSetRGBFillColor(ctx, col.r, col.g, col.b, t);
            CGFloat s = p->size * t;
            CGContextFillRect(ctx, CGRectMake(cx - s * 0.5, cy - s * 0.5, s, s));
        }
    }
}

#pragma mark - 60 FPS Tick

- (void)tick {
    double now = CACurrentMediaTime();
    float rawDt = (float)(now - _lastFrameTime);
    _lastFrameTime = now;
    _dt = TPClampf(rawDt, 0.001f, 0.05f);
    _time += _dt;

    // Sample global mouse X position cleanly (works across all apps with zero permissions!)
    if (_mouseReactive) {
        NSPoint ml = [NSEvent mouseLocation];
        NSScreen *mainScreen = [NSScreen mainScreen];
        CGFloat sw = mainScreen ? mainScreen.frame.size.width : 1440.0;
        if (sw > 1.0) {
            float targetX = TPClampf((float)(ml.x / sw), 0.0f, 1.0f);
            _mouseNormX = TPLerpf(_mouseNormX, targetX, TPClampf(_dt * 14.0f, 0.0f, 1.0f));
        }
    }

    if (_modeFlash > 0.0f) {
        _modeFlash = MAX(0.0f, _modeFlash - _dt * 3.2f);
    }

    float scaledDt = _dt * _speedScale;

    // Step Pomodoro timer & HUD kinetic scroll physics
    [self stepTools:_dt];

    switch (_mode) {
        case TPModePlasma:   [self stepPlasma:scaledDt]; break;
        case TPModeWarp:     [self stepWarp:scaledDt]; break;
        case TPModeFire:     [self stepFire:scaledDt]; break;
        case TPModeMatrix:   [self stepMatrix:scaledDt]; break;
        case TPModeBeatbox:  [self stepBeatbox:scaledDt]; break;
        case TPModePhysics:  [self stepPhysics:scaledDt]; break;
        case TPModeRunner:   [self stepRunner:scaledDt]; break;
        case TPModeBlaster:  [self stepBlaster:scaledDt]; break;
        case TPModeSynth:    [self stepSynth:_dt]; break;
        case TPModePet:      [self stepPet:scaledDt]; break;
        case TPModeSpectrum: [self stepSpectrum:_dt]; break;
        case TPModeTools:    break;
        default: break;
    }

    [self stepParticles:_dt];
    _frameCount++;

    // Smart redraw throttling:
    // - Power HUD runs FULL 45 FPS while sliding/gliding/animating, drops to 15 FPS when still!
    BOOL anyParticle = NO;
    if (_mode == TPModeTools) {
        for (int i = 0; i < TP_MAX_PARTICLES; i++) {
            if (_particles[i].active) { anyParticle = YES; break; }
        }
    }
    BOOL hudMoving = (_hudIsDragging || fabs(_hudScrollVel) > 1.5 || _hudTapFeedbackLife > 0.01f);
    BOOL toolsSkipFrame = (_mode == TPModeTools && !hudMoving && !anyParticle && _modeFlash <= 0.01f && _pomoFlash <= 0.01f && (_frameCount % 3 != 0));

    if (!toolsSkipFrame) {
        for (NSView *v in _displayViews) {
            if (!v || v.hidden) continue;
            // On-screen mirror window view doesn't need full 45fps redraws while real Touch Bar runs full speed
            if (v.frame.size.width < 900.0 && v.window && !v.window.isMiniaturized && [v respondsToSelector:@selector(isHardwareTouchBar)]) {
                BOOL isHW = [[v valueForKey:@"isHardwareTouchBar"] boolValue];
                if (!isHW && (_frameCount & 1)) continue;
            }
            [v setNeedsDisplay:YES];
        }
    }
}

#pragma mark - Unified Touch Input

- (CGRect)activeRectForSize:(CGSize)size {
    CGFloat x0 = _showModePill ? TP_MODE_PILL_WIDTH : 0.0;
    return CGRectMake(x0, 0, MAX(1.0, size.width - x0), size.height);
}

- (int)findTouchSlot:(uint64_t)touchID {
    for (int i = 0; i < TP_MAX_TOUCHES; i++) {
        if (_touches[i].active && _touches[i].touchID == touchID) return i;
    }
    return -1;
}

- (int)activeTouchCount {
    int c = 0;
    for (int i = 0; i < TP_MAX_TOUCHES; i++) {
        if (_touches[i].active) c++;
    }
    return c;
}

- (void)handleTouchBeganID:(uint64_t)touchID point:(CGPoint)pt inSize:(CGSize)size {
    if (size.width <= 1.0 || size.height <= 1.0) return;

    // Left-edge mode switcher pill tap
    if (_showModePill && pt.x <= TP_MODE_PILL_WIDTH) {
        [self cycleNextMode];
        return;
    }

    CGRect ar = [self activeRectForSize:size];
    float nx = TPClampf((float)((pt.x - ar.origin.x) / ar.size.width), 0.0f, 1.0f);
    float ny = TPClampf((float)(pt.y / ar.size.height), 0.0f, 1.0f);

    // Allocate touch slot
    int slot = [self findTouchSlot:touchID];
    if (slot < 0) {
        for (int i = 0; i < TP_MAX_TOUCHES; i++) {
            if (!_touches[i].active) { slot = i; break; }
        }
    }
    if (slot >= 0) {
        TPActiveTouch *t = &_touches[slot];
        t->active = YES;
        t->touchID = touchID;
        t->x = nx;
        t->y = ny;
        t->prevX = nx;
        t->prevY = ny;
        t->startX = nx;
        t->startY = ny;
        t->vx = 0.0f;
        t->vy = 0.0f;
        t->startTime = CACurrentMediaTime();
        t->lastStringIndex = -1;
    }

    // Check 3-finger simultaneous tap to quick-cycle theme!
    if ([self activeTouchCount] == 3 && (CACurrentMediaTime() - _lastThreeFingerSwitch) > 0.55) {
        _lastThreeFingerSwitch = CACurrentMediaTime();
        [self cycleNextTheme];
        return;
    }

    switch (_mode) {
        case TPModePlasma:   [self touchPlasmaBegan:nx y:ny]; break;
        case TPModeWarp:     break;
        case TPModeFire:     [self touchFireBegan:nx y:ny]; break;
        case TPModeMatrix:   [self touchMatrixBegan:nx y:ny]; break;
        case TPModeBeatbox:  [self touchBeatboxBegan:nx y:ny]; break;
        case TPModePhysics:  [self touchPhysicsBegan:nx y:ny]; break;
        case TPModeRunner:   [self touchRunnerBegan:nx y:ny]; break;
        case TPModeBlaster:  [self touchBlasterBegan:nx y:ny]; break;
        case TPModeSynth:    if (slot >= 0) [self touchSynthAt:&_touches[slot] isNew:YES]; break;
        case TPModePet:      [self touchPetBegan:nx y:ny]; break;
        case TPModeSpectrum: [self touchSpectrumAt:nx y:ny strong:YES]; break;
        case TPModeTools:    [self touchToolsBeganID:touchID point:pt rect:ar]; break;
        default: break;
    }
}

- (void)handleTouchMovedID:(uint64_t)touchID point:(CGPoint)pt inSize:(CGSize)size {
    int slot = [self findTouchSlot:touchID];
    if (slot < 0) return;

    CGRect ar = [self activeRectForSize:size];
    float nx = TPClampf((float)((pt.x - ar.origin.x) / ar.size.width), 0.0f, 1.0f);
    float ny = TPClampf((float)(pt.y / ar.size.height), 0.0f, 1.0f);

    TPActiveTouch *t = &_touches[slot];
    t->prevX = t->x;
    t->prevY = t->y;
    t->x = nx;
    t->y = ny;
    float invDt = 1.0f / MAX(0.008f, _dt);
    t->vx = (t->x - t->prevX) * invDt;
    t->vy = (t->y - t->prevY) * invDt;

    switch (_mode) {
        case TPModePlasma:   [self touchPlasmaMoved:nx y:ny vx:t->vx vy:t->vy]; break;
        case TPModeFire:     [self touchFireMoved:nx y:ny vx:t->vx vy:t->vy]; break;
        case TPModeMatrix:   [self touchMatrixMoved:nx y:ny]; break;
        case TPModePhysics:  [self touchPhysicsMoved:nx y:ny vx:t->vx vy:t->vy]; break;
        case TPModeSynth:    [self touchSynthAt:t isNew:NO]; break;
        case TPModePet:      [self touchPetMoved:nx y:ny]; break;
        case TPModeSpectrum: [self touchSpectrumAt:nx y:ny strong:NO]; break;
        case TPModeTools:    [self touchToolsMovedID:touchID point:pt rect:ar]; break;
        default: break;
    }
}

- (void)handleTouchEndedID:(uint64_t)touchID point:(CGPoint)pt inSize:(CGSize)size {
    int slot = [self findTouchSlot:touchID];
    if (slot < 0) return;
    CGRect ar = [self activeRectForSize:size];
    float nx = _touches[slot].x;
    float ny = _touches[slot].y;
    float vx = _touches[slot].vx;
    float vy = _touches[slot].vy;
    _touches[slot].active = NO;

    switch (_mode) {
        case TPModePlasma:  [self touchPlasmaEnded:nx y:ny vx:vx vy:vy]; break;
        case TPModeWarp:    [self touchWarpEnded:nx y:ny]; break;
        case TPModePhysics: [self touchPhysicsEnded:nx y:ny]; break;
        case TPModeTools:   [self touchToolsEndedID:touchID point:pt rect:ar]; break;
        default: break;
    }
}

- (void)cancelAllTouches {
    for (int i = 0; i < TP_MAX_TOUCHES; i++) {
        _touches[i].active = NO;
    }
}

#pragma mark - Master Renderer

- (void)renderInContext:(CGContextRef)ctx size:(CGSize)size {
    if (size.width <= 1.0 || size.height <= 1.0) return;
    _lastCanvasWidth = size.width;

    // Pure OLED deep black canvas
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));

    CGRect activeRect = [self activeRectForSize:size];

    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, activeRect);

    switch (_mode) {
        case TPModePlasma:   [self renderPlasma:ctx rect:activeRect]; break;
        case TPModeWarp:     [self renderWarp:ctx rect:activeRect]; break;
        case TPModeFire:     [self renderFire:ctx rect:activeRect]; break;
        case TPModeMatrix:   [self renderMatrix:ctx rect:activeRect]; break;
        case TPModeBeatbox:  [self renderBeatbox:ctx rect:activeRect]; break;
        case TPModePhysics:  [self renderPhysics:ctx rect:activeRect]; break;
        case TPModeRunner:   [self renderRunner:ctx rect:activeRect]; break;
        case TPModeBlaster:  [self renderBlaster:ctx rect:activeRect]; break;
        case TPModeSynth:    [self renderSynth:ctx rect:activeRect]; break;
        case TPModePet:      [self renderPet:ctx rect:activeRect]; break;
        case TPModeSpectrum: [self renderSpectrum:ctx rect:activeRect]; break;
        case TPModeTools:    [self renderTools:ctx rect:activeRect]; break;
        default: break;
    }

    // Render unified glowing sparks/hearts/shatter particles
    [self renderParticles:ctx rect:activeRect];

    // Subtle flash sweep on mode/theme switch
    if (_modeFlash > 0.01f) {
        TPRGBA fc = TPThemeColor(_theme, fmodf((float)_time * 0.5f, 1.0f), _modeFlash * 0.25f);
        CGContextSetRGBFillColor(ctx, fc.r, fc.g, fc.b, fc.a);
        CGContextFillRect(ctx, activeRect);
    }

    // Floating HUD toast on mode/theme change
    double now = CACurrentMediaTime();
    if (_hudTitle && now < _hudUntil) {
        float rem = (float)(_hudUntil - now);
        float alpha = TPClampf(rem / 0.35f, 0.0f, 1.0f);
        NSString *label = [NSString stringWithFormat:@"%@  %@", TPModeSymbol(_mode), [_hudTitle uppercaseString]];
        CGSize ts = TPMeasureText(label, 11.0, NSFontWeightBold, NO);
        CGFloat padX = 12.0;
        CGFloat pillW = ts.width + padX * 2.0;
        CGFloat pillH = 22.0;
        CGRect pill = CGRectMake(activeRect.origin.x + (activeRect.size.width - pillW) * 0.5,
                                 (size.height - pillH) * 0.5,
                                 pillW, pillH);
        TPDrawRoundedRect(ctx, pill, 11.0);
        CGContextSetRGBFillColor(ctx, 0.04, 0.05, 0.09, 0.86 * alpha);
        CGContextFillPath(ctx);

        TPRGBA borderC = TPThemeColor(_theme, fmodf((float)_time * 0.6f, 1.0f), 0.9 * alpha);
        TPDrawRoundedRect(ctx, CGRectInset(pill, 0.5, 0.5), 10.5);
        CGContextSetRGBStrokeColor(ctx, borderC.r, borderC.g, borderC.b, borderC.a);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokePath(ctx);

        TPDrawText(ctx, label,
                   CGPointMake(pill.origin.x + padX, pill.origin.y + (pillH - ts.height) * 0.5 - 0.5),
                   11.0, NSFontWeightBold, [NSColor colorWithWhite:1.0 alpha:alpha], NO);
    }

    CGContextRestoreGState(ctx);

    // Left-edge quick mode-cycle button
    if (_showModePill) {
        CGRect pillR = CGRectMake(2.0, 2.0, TP_MODE_PILL_WIDTH - 5.0, size.height - 4.0);
        TPDrawRoundedRect(ctx, pillR, 6.0);
        CGContextSetRGBFillColor(ctx, 0.11, 0.12, 0.17, 0.95);
        CGContextFillPath(ctx);

        TPRGBA glow = TPThemeColor(_theme, fmodf((float)_time * 0.25f, 1.0f), 0.88f);
        TPDrawRoundedRect(ctx, CGRectInset(pillR, 0.5, 0.5), 5.5);
        CGContextSetRGBStrokeColor(ctx, glow.r, glow.g, glow.b, 0.72f);
        CGContextSetLineWidth(ctx, 1.1);
        CGContextStrokePath(ctx);

        NSString *sym = TPModeSymbol(_mode);
        CGSize ss = TPMeasureText(sym, 12.0, NSFontWeightBold, NO);
        TPDrawText(ctx, sym,
                   CGPointMake(pillR.origin.x + (pillR.size.width - ss.width) * 0.5,
                               pillR.origin.y + (pillR.size.height - ss.height) * 0.5),
                   12.0, NSFontWeightBold,
                   [NSColor colorWithRed:glow.r green:glow.g blue:glow.b alpha:1.0], NO);

        // Subtle Pomodoro active indicator dot on mode pill when running in another mode!
        if (_pomoRunning && _mode != TPModeTools) {
            float pulse = 0.55f + 0.45f * sinf((float)_time * 4.5f);
            CGContextSetRGBFillColor(ctx, 1.0, 0.42, 0.22, pulse);
            CGContextFillEllipseInRect(ctx, CGRectMake(pillR.origin.x + pillR.size.width - 6.0,
                                                       pillR.origin.y + pillR.size.height - 6.0, 4.0, 4.0));
        }
    }
}

@end

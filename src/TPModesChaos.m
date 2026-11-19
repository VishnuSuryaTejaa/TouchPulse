#import "TPEngine.h"
#import <math.h>

static NSString *const kMatrixGlyphs[] = {
    @"0", @"1", @"7", @"9", @"A", @"F", @"X", @"Z",
    @"ｱ", @"ｲ", @"ｳ", @"ｴ", @"ｵ", @"ｶ", @"ｷ", @"ｸ",
    @"ｹ", @"ｺ", @"ｻ", @"ｼ", @"ｽ", @"ｾ", @"ｿ", @"ﾀ",
    @"ﾁ", @"ﾂ", @"ﾃ", @"ﾄ", @"ﾅ", @"ﾆ", @"ﾇ", @"ﾈ",
    @"Ψ", @"Ω", @"Σ", @"Λ", @"Δ", @"¥", @"#", @"@"
};
static const int kMatrixGlyphCount = 40;

static NSString *const kBreachAlerts[] = {
    @"⚡ MAINFRAME BREACHED",
    @"◉ ACCESS GRANTED // ROOT",
    @"✦ NEURAL UPLINK 100%",
    @"▲ FIREWALL BYPASSED",
    @"◈ QUANTUM OVERCLOCK ON",
    @"⚡ SYSTEM KERNEL UNLOCKED"
};
static const int kBreachAlertCount = 6;

@implementation TPEngine (ChaosModes)

- (void)initChaosModes {
    // 1. Seed Cellular Fire bottom heat row
    memset(_fireGrid, 0, sizeof(_fireGrid));
    for (int x = 0; x < TP_FIRE_W; x++) {
        _fireGrid[0][x] = TPRandRange(0.75f, 1.0f);
    }
    _autoRocketTimer = 1.8f;

    // 2. Seed Matrix Digital Rain columns
    for (int i = 0; i < TP_MATRIX_COLS; i++) {
        _matrixCols[i].y = TPRandRange(0.0f, 32.0f);
        _matrixCols[i].speed = TPRandRange(18.0f, 46.0f);
        _matrixCols[i].glyphSeed = (int)arc4random_uniform(10000);
        _matrixCols[i].length = TPRandRange(10.0f, 26.0f);
        _matrixCols[i].glitch = 0.0f;
    }

    // 3. Pre-load a sick cyberpunk 808 + Acid 303 groove in Beatbox!
    _beatPlaying = YES;
    _beatCurrentStep = 0;
    _beatStepTimer = 0.0f;
    memset(_beatGrid, 0, sizeof(_beatGrid));
    // Track 0: 808 Kick (punchy four-on-the-floor / syncopated cyber groove)
    int kicks[]  = { 0, 3, 6, 8, 10, 14 };
    int snares[] = { 4, 12 };
    int hats[]   = { 0, 2, 4, 6, 8, 10, 12, 14, 15 };
    int acids[]  = { 0, 2, 5, 7, 10, 13, 15 };
    for (size_t i = 0; i < sizeof(kicks)/sizeof(int); i++)  _beatGrid[0][kicks[i]] = YES;
    for (size_t i = 0; i < sizeof(snares)/sizeof(int); i++) _beatGrid[1][snares[i]] = YES;
    for (size_t i = 0; i < sizeof(hats)/sizeof(int); i++)   _beatGrid[2][hats[i]] = YES;
    for (size_t i = 0; i < sizeof(acids)/sizeof(int); i++)  _beatGrid[3][acids[i]] = YES;

    // 4. Seed 78 Liquid Mercury Physics Orbs
    for (int i = 0; i < TP_PHYS_ORBS; i++) {
        _orbs[i].x = TPRandRange(0.04f, 0.96f);
        _orbs[i].y = TPRandRange(4.0f, 26.0f);
        _orbs[i].vx = TPRandRange(-0.18f, 0.18f);
        _orbs[i].vy = TPRandRange(-20.0f, 20.0f);
        _orbs[i].radius = TPRandRange(2.4f, 4.8f);
        _orbs[i].hue = (float)i / (float)TP_PHYS_ORBS;
        _orbs[i].energy = 0.35f;
    }
}

#pragma mark - Mode 2: Inferno Cellular Fire & Starburst Fireworks

- (void)launchFireworkAtX:(float)nx {
    for (int i = 0; i < TP_MAX_ROCKETS; i++) {
        if (!_rockets[i].active) {
            TPFireworkRocket *rk = &_rockets[i];
            rk->active = YES;
            rk->x = TPClampf(nx, 0.04f, 0.96f);
            rk->y = 2.0f;
            rk->vx = TPRandRange(-0.08f, 0.08f);
            rk->vy = TPRandRange(42.0f, 64.0f);
            rk->fuse = TPRandRange(0.24f, 0.42f);
            rk->hue = TPRandf();
            [[TPAudioEngine shared] playSFX:TPSFXJump pan:nx * 2.0f - 1.0f pitchScale:1.45f];
            return;
        }
    }
}

- (void)detonateFirework:(TPFireworkRocket *)rk {
    rk->active = NO;
    [[TPAudioEngine shared] playSFX:TPSFXFirework pan:rk->x * 2.0f - 1.0f pitchScale:TPRandRange(0.85f, 1.25f)];

    // Massive glittering starburst shower!
    for (int p = 0; p < 34; p++) {
        float ang = ((float)p / 34.0f) * 6.28318f + TPRandRange(-0.15f, 0.15f);
        float spd = TPRandRange(0.06f, 0.36f);
        [self spawnParticleX:rk->x
                           y:TPClampf(rk->y, 6.0f, 25.0f)
                          vx:cosf(ang) * spd
                          vy:sinf(ang) * 48.0f
                        life:TPRandRange(0.45f, 1.15f)
                        size:TPRandRange(2.2f, 5.4f)
                         hue:fmodf(rk->hue + TPRandRange(-0.12f, 0.12f), 1.0f)
                        kind:(p % 3 == 0) ? 1 : 0];
    }
    // Flash heat burst into the cellular fire buffer
    int cx = (int)TPClampf(rk->x * (TP_FIRE_W - 1), 3, TP_FIRE_W - 4);
    for (int dx = -5; dx <= 5; dx++) {
        for (int dy = 0; dy < 5; dy++) {
            int gx = cx + dx;
            int gy = MIN(TP_FIRE_H - 1, dy + 4);
            if (gx >= 0 && gx < TP_FIRE_W) _fireGrid[gy][gx] = 1.0f;
        }
    }
}

- (void)stepFire:(float)dt {
    _fireWind *= powf(0.08f, dt);

    // Bottom fuel bed with lively turbulence
    for (int x = 0; x < TP_FIRE_W; x++) {
        float wave = 0.72f + 0.28f * sinf((float)x * 0.19f + (float)_time * 7.5f);
        _fireGrid[0][x] = TPClampf(wave + TPRandRange(-0.22f, 0.28f), 0.35f, 1.0f);
    }

    // Active finger touches act as blazing flamethrowers!
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        int cx = (int)TPClampf(_touches[k].x * (TP_FIRE_W - 1), 2, TP_FIRE_W - 3);
        int cy = (int)TPClampf(_touches[k].y * (TP_FIRE_H - 1), 0, TP_FIRE_H - 2);
        for (int dx = -4; dx <= 4; dx++) {
            for (int dy = -2; dy <= 2; dy++) {
                int gx = cx + dx;
                int gy = cy + dy;
                if (gx >= 0 && gx < TP_FIRE_W && gy >= 0 && gy < TP_FIRE_H) {
                    _fireGrid[gy][gx] = 1.0f;
                }
            }
        }
        _fireWind = TPClampf(_fireWind + _touches[k].vx * 1.4f * dt, -2.5f, 2.5f);
    }

    // Classic Doom-style upward cellular fire propagation
    int windShift = (int)lroundf(_fireWind);
    for (int y = TP_FIRE_H - 1; y >= 1; y--) {
        for (int x = 0; x < TP_FIRE_W; x++) {
            int jitter = (int)(arc4random_uniform(3)) - 1 - windShift;
            int sx = x + jitter;
            if (sx < 0) sx = 0;
            if (sx >= TP_FIRE_W) sx = TP_FIRE_W - 1;
            float below = _fireGrid[y - 1][sx];
            float cool = TPRandRange(0.035f, 0.135f);
            _fireGrid[y][x] = MAX(0.0f, below - cool);
        }
    }

    // Occasional automatic ambient firework
    _autoRocketTimer -= dt;
    if (_autoRocketTimer <= 0.0f) {
        [self launchFireworkAtX:TPRandRange(0.12f, 0.88f)];
        _autoRocketTimer = TPRandRange(2.4f, 4.8f);
    }

    // Step rockets
    for (int i = 0; i < TP_MAX_ROCKETS; i++) {
        TPFireworkRocket *rk = &_rockets[i];
        if (!rk->active) continue;
        rk->x = TPClampf(rk->x + rk->vx * dt, 0.02f, 0.98f);
        rk->y = TPClampf(rk->y + rk->vy * dt, 2.0f, 26.0f);
        rk->vy *= (1.0f - dt * 1.5f);
        rk->fuse -= dt;
        // Rocket spark trail
        [self spawnParticleX:rk->x
                           y:rk->y
                          vx:TPRandRange(-0.02f, 0.02f)
                          vy:TPRandRange(-18.0f, -6.0f)
                        life:0.22f
                        size:2.4f
                         hue:0.12f
                        kind:0];
        if (rk->fuse <= 0.0f || rk->y >= 24.5f) {
            [self detonateFirework:rk];
        }
    }
}

- (void)touchFireBegan:(float)nx y:(float)ny {
    [self launchFireworkAtX:nx];
}

- (void)touchFireMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy {
    _fireWind = TPClampf(vx * 3.0f, -2.5f, 2.5f);
    for (int i = 0; i < 3; i++) {
        [self spawnParticleX:nx
                           y:ny * 28.0f
                          vx:vx * 0.35f + TPRandRange(-0.06f, 0.06f)
                          vy:TPRandRange(10.0f, 38.0f)
                        life:TPRandRange(0.28f, 0.6f)
                        size:TPRandRange(2.5f, 5.2f)
                         hue:TPRandRange(0.02f, 0.18f)
                        kind:1];
    }
}

static inline void TPFireColor(float heat, float *r, float *g, float *b) {
    // Blazing inferno palette: black -> crimson -> orange -> molten gold -> white-hot
    if (heat < 0.33f) {
        float t = heat / 0.33f;
        *r = t * 0.95f; *g = t * 0.08f; *b = 0.02f * t;
    } else if (heat < 0.66f) {
        float t = (heat - 0.33f) / 0.33f;
        *r = 0.95f + 0.05f * t; *g = 0.08f + 0.66f * t; *b = 0.02f;
    } else {
        float t = (heat - 0.66f) / 0.34f;
        *r = 1.0f; *g = 0.74f + 0.26f * t; *b = 0.02f + 0.92f * t;
    }
}

- (void)renderFire:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat cellW = w / (CGFloat)TP_FIRE_W;
    CGFloat cellH = h / (CGFloat)TP_FIRE_H;

    // Render roaring 2D cellular fire (stride 2 horizontally for ultra-crisp retro OLED speed!)
    for (int y = 0; y < TP_FIRE_H; y++) {
        CGFloat py = r.origin.y + (CGFloat)y * cellH;
        for (int x = 0; x < TP_FIRE_W; x += 2) {
            float heat = (_fireGrid[y][x] + _fireGrid[y][MIN(TP_FIRE_W - 1, x + 1)]) * 0.5f;
            if (heat < 0.08f) continue;
            float cr, cg, cb;
            TPFireColor(TPClampf(heat, 0.0f, 1.0f), &cr, &cg, &cb);
            CGContextSetRGBFillColor(ctx, cr, cg, cb, TPClampf(heat * 1.15f, 0.0f, 1.0f));
            CGContextFillRect(ctx, CGRectMake(r.origin.x + (CGFloat)x * cellW, py, cellW * 2.15, cellH + 0.4));
        }
    }

    // Active rockets soaring upward
    for (int i = 0; i < TP_MAX_ROCKETS; i++) {
        TPFireworkRocket *rk = &_rockets[i];
        if (!rk->active) continue;
        CGFloat rx = r.origin.x + rk->x * w;
        CGFloat ry = r.origin.y + rk->y;
        TPDrawGlowCircle(ctx, rx, ry, 5.5f, (TPRGBA){1.0f, 0.96f, 0.75f, 1.0f});
    }
}

#pragma mark - Mode 3: Matrix Digital Rain + Cyberpunk Breach

- (void)triggerMatrixBreachAt:(float)nx {
    int center = (int)TPClampf(nx * (TP_MATRIX_COLS - 1), 0, TP_MATRIX_COLS - 1);
    for (int d = -9; d <= 9; d++) {
        int c = center + d;
        if (c >= 0 && c < TP_MATRIX_COLS) {
            float f = 1.0f - fabsf((float)d) / 10.0f;
            _matrixCols[c].glitch = MAX(_matrixCols[c].glitch, f);
            _matrixCols[c].glyphSeed += (int)arc4random_uniform(19) + 1;
            _matrixCols[c].speed = TPRandRange(35.0f, 68.0f);
        }
    }
    _breachTimer = 1.35f;
    _breachX = nx;
    _breachBanner = kBreachAlerts[arc4random_uniform(kBreachAlertCount)];
    [[TPAudioEngine shared] playSFX:TPSFXGlitch pan:nx * 2.0f - 1.0f pitchScale:TPRandRange(0.75f, 1.45f)];
    for (int i = 0; i < 14; i++) {
        [self spawnParticleX:nx
                           y:TPRandRange(4.0f, 26.0f)
                          vx:TPRandRange(-0.22f, 0.22f)
                          vy:TPRandRange(-25.0f, 25.0f)
                        life:0.42f
                        size:2.6f
                         hue:0.35f
                        kind:3];
    }
}

- (void)stepMatrix:(float)dt {
    if (_breachTimer > 0.0f) {
        _breachTimer = MAX(0.0f, _breachTimer - dt);
    }

    for (int i = 0; i < TP_MATRIX_COLS; i++) {
        TPMatrixCol *col = &_matrixCols[i];
        col->y -= col->speed * dt;
        if (col->glitch > 0.0f) {
            col->glitch = MAX(0.0f, col->glitch - dt * 1.4f);
            if (TPRandf() < 0.45f) col->glyphSeed++;
        } else if (TPRandf() < 0.06f) {
            col->glyphSeed++;
        }
        if (col->y < -col->length) {
            col->y = 31.0f + TPRandRange(0.0f, 12.0f);
            col->speed = TPRandRange(16.0f, 44.0f);
            col->length = TPRandRange(10.0f, 26.0f);
            col->glyphSeed = (int)arc4random_uniform(10000);
        }
    }
}

- (void)touchMatrixBegan:(float)nx y:(float)ny {
    [self triggerMatrixBreachAt:nx];
}

- (void)touchMatrixMoved:(float)nx y:(float)ny {
    int center = (int)TPClampf(nx * (TP_MATRIX_COLS - 1), 0, TP_MATRIX_COLS - 1);
    for (int d = -4; d <= 4; d++) {
        int c = center + d;
        if (c >= 0 && c < TP_MATRIX_COLS) {
            _matrixCols[c].glitch = 1.0f;
            _matrixCols[c].glyphSeed += 3;
        }
    }
}

- (void)renderMatrix:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat colW = w / (CGFloat)TP_MATRIX_COLS;

    // Matrix phosphor green base (shifts with non-Matrix themes too while keeping hacker aesthetic!)
    TPRGBA baseCol = (_theme == TPThemeMatrix || _theme == TPThemeCyberpunk)
        ? (TPRGBA){0.08f, 1.0f, 0.36f, 1.0f}
        : TPThemeColor(_theme, 0.35f, 1.0f);

    for (int i = 0; i < TP_MATRIX_COLS; i++) {
        TPMatrixCol *col = &_matrixCols[i];
        CGFloat x = r.origin.x + (CGFloat)i * colW;
        BOOL glitching = (col->glitch > 0.05f);

        // Draw vertical fading stream of 4 crisp glyphs per column
        for (int s = 0; s < 4; s++) {
            CGFloat gy = col->y + (CGFloat)s * 7.2;
            if (gy < -6.0 || gy > h + 2.0) continue;
            float fade = TPClampf(1.0f - ((float)s * 7.2f / MAX(6.0f, col->length)), 0.0f, 1.0f);
            if (fade <= 0.05f) continue;

            NSString *glyph = kMatrixGlyphs[(col->glyphSeed + s * 7 + i * 3) % kMatrixGlyphCount];
            if (glitching) {
                // RGB Chromatic Aberration Glitch!
                CGFloat jx = TPRandRange(-3.0, 3.0) * col->glitch;
                TPDrawText(ctx, glyph, CGPointMake(x + jx - 1.5, r.origin.y + gy), 8.5, NSFontWeightBold,
                           [NSColor colorWithRed:1.0 green:0.12 blue:0.32 alpha:fade], YES);
                TPDrawText(ctx, glyph, CGPointMake(x + jx + 1.5, r.origin.y + gy), 8.5, NSFontWeightBold,
                           [NSColor colorWithRed:0.0 green:0.95 blue:1.0 alpha:fade], YES);
            } else {
                NSColor *gc = (s == 0)
                    ? [NSColor colorWithRed:0.86 green:1.0 blue:0.92 alpha:0.98]
                    : [NSColor colorWithRed:baseCol.r green:baseCol.g blue:baseCol.b alpha:fade * 0.85];
                TPDrawText(ctx, glyph, CGPointMake(x, r.origin.y + gy), 8.5,
                           (s == 0 ? NSFontWeightBold : NSFontWeightRegular), gc, YES);
            }
        }
    }

    // Glitch Breach Alert Banner!
    if (_breachTimer > 0.05f && _breachBanner) {
        float a = TPClampf(_breachTimer / 0.35f, 0.0f, 1.0f);
        CGSize bs = TPMeasureText(_breachBanner, 10.5, NSFontWeightHeavy, YES);
        CGFloat bw = bs.width + 20.0;
        CGFloat bx = TPClampf(r.origin.x + _breachX * w - bw * 0.5, r.origin.x + 8.0, r.origin.x + w - bw - 8.0);
        CGRect box = CGRectMake(bx, r.origin.y + 4.0, bw, h - 8.0);
        TPDrawRoundedRect(ctx, box, 5.0);
        CGContextSetRGBFillColor(ctx, 0.02, 0.09, 0.05, 0.90 * a);
        CGContextFillPath(ctx);
        TPDrawRoundedRect(ctx, CGRectInset(box, 0.5, 0.5), 4.5);
        CGContextSetRGBStrokeColor(ctx, 0.15, 1.0, 0.45, 0.95 * a);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokePath(ctx);
        TPDrawText(ctx, _breachBanner,
                   CGPointMake(box.origin.x + 10.0, box.origin.y + (box.size.height - bs.height) * 0.5),
                   10.5, NSFontWeightHeavy, [NSColor colorWithRed:0.65 green:1.0 blue:0.75 alpha:a], YES);
    }
}

#pragma mark - Mode 4: 808 Beatbox & 303 Acid Sequencer

- (void)toggleBeatboxPlaying {
    _beatPlaying = !_beatPlaying;
    [[TPAudioEngine shared] playSFX:TPSFXClick pan:-0.8f pitchScale:_beatPlaying ? 1.3f : 0.75f];
}

- (void)randomizeBeatbox {
    memset(_beatGrid, 0, sizeof(_beatGrid));
    for (int s = 0; s < TP_BEAT_STEPS; s++) {
        // Musical rhythm probabilities so random beats ALWAYS slap!
        _beatGrid[0][s] = (s % 4 == 0) ? (TPRandf() < 0.85f) : (TPRandf() < 0.22f); // Kick
        _beatGrid[1][s] = (s == 4 || s == 12) ? YES : (TPRandf() < 0.14f);          // Snare
        _beatGrid[2][s] = (s % 2 == 0) ? (TPRandf() < 0.82f) : (TPRandf() < 0.35f); // HiHat
        _beatGrid[3][s] = (TPRandf() < 0.42f);                                      // Acid 303
    }
    _beatPlaying = YES;
    [[TPAudioEngine shared] playSFX:TPSFXCoin pan:0.0f pitchScale:1.15f];
    [self showToast:@"NEW 808 GROOVE!" subtitle:@"Tap pads: Bottom=Kick • Mid=Snare • Top=Acid"];
}

- (void)stepBeatbox:(float)dt {
    if (_beatKickFlash > 0.0f) _beatKickFlash = MAX(0.0f, _beatKickFlash - dt * 5.0f);
    for (int s = 0; s < TP_BEAT_STEPS; s++) {
        _beatStepGlow[s] = MAX(0.0f, _beatStepGlow[s] - dt * 4.5f);
    }

    if (!_beatPlaying) return;

    // 16th note interval at 124 BPM (scaled by engine speed!)
    float stepDur = 60.0f / (124.0f * 4.0f);
    _beatStepTimer += dt;
    if (_beatStepTimer >= stepDur) {
        _beatStepTimer -= stepDur;
        int st = _beatCurrentStep;
        _beatStepGlow[st] = 1.0f;

        float pan = ((float)st / (float)(TP_BEAT_STEPS - 1)) * 1.4f - 0.7f;
        float stepNormX = 0.09f + ((float)st + 0.5f) / (float)TP_BEAT_STEPS * 0.90f;

        if (_beatGrid[0][st]) {
            [[TPAudioEngine shared] playSFX:TPSFXKick808 pan:0.0f pitchScale:1.0f];
            _beatKickFlash = 1.0f;
            for (int p = 0; p < 5; p++) {
                [self spawnParticleX:stepNormX y:5.0f vx:TPRandRange(-0.05f, 0.05f) vy:TPRandRange(10.0f, 28.0f)
                                life:0.25f size:3.2f hue:0.95f kind:0];
            }
        }
        if (_beatGrid[1][st]) {
            [[TPAudioEngine shared] playSFX:TPSFXSnare808 pan:pan * 0.4f pitchScale:1.0f];
            for (int p = 0; p < 4; p++) {
                [self spawnParticleX:stepNormX y:15.0f vx:TPRandRange(-0.06f, 0.06f) vy:TPRandRange(-16.0f, 16.0f)
                                life:0.22f size:2.8f hue:0.52f kind:3];
            }
        }
        if (_beatGrid[2][st]) {
            [[TPAudioEngine shared] playSFX:TPSFXHiHat pan:pan * 0.7f pitchScale:1.0f];
        }
        if (_beatGrid[3][st]) {
            static const float acidRatios[8] = { 1.0f, 1.189f, 1.335f, 1.498f, 1.782f, 2.0f, 1.498f, 1.189f };
            float pitch = acidRatios[st % 8];
            [[TPAudioEngine shared] playSFX:TPSFXAcid303 pan:pan pitchScale:pitch];
            [self spawnParticleX:stepNormX y:25.0f vx:0.0f vy:TPRandRange(-14.0f, 10.0f)
                            life:0.28f size:3.5f hue:0.16f kind:0];
        }

        _beatCurrentStep = (_beatCurrentStep + 1) % TP_BEAT_STEPS;
    }
}

- (void)touchBeatboxBegan:(float)nx y:(float)ny {
    // Left mini control zone: 0..0.045 = Play/Pause, 0.045..0.09 = Randomize!
    if (nx < 0.045f) {
        [self toggleBeatboxPlaying];
        return;
    }
    if (nx < 0.09f) {
        [self randomizeBeatbox];
        return;
    }

    int step = (int)TPClampf(((nx - 0.09f) / 0.91f) * (float)TP_BEAT_STEPS, 0, TP_BEAT_STEPS - 1);
    // Tap vertical row: Bottom = Kick (0), Middle = Snare/Hat (1 & 2), Top = Acid 303 (3)
    if (ny < 0.36f) {
        _beatGrid[0][step] = !_beatGrid[0][step];
        if (_beatGrid[0][step]) [[TPAudioEngine shared] playSFX:TPSFXKick808 pan:0.0f pitchScale:1.0f];
    } else if (ny < 0.68f) {
        _beatGrid[1][step] = !_beatGrid[1][step];
        _beatGrid[2][step] = !_beatGrid[2][step];
        if (_beatGrid[1][step]) [[TPAudioEngine shared] playSFX:TPSFXSnare808 pan:0.0f pitchScale:1.0f];
    } else {
        _beatGrid[3][step] = !_beatGrid[3][step];
        if (_beatGrid[3][step]) [[TPAudioEngine shared] playSFX:TPSFXAcid303 pan:nx * 2.0f - 1.0f pitchScale:1.335f];
    }
    _beatStepGlow[step] = 1.0f;
}

- (void)renderBeatbox:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;

    // Subtle bass-kick full-bar pulse backdrop
    if (_beatKickFlash > 0.01f) {
        TPRGBA kc = TPThemeColor(_theme, 0.95f, _beatKickFlash * 0.22f);
        CGContextSetRGBFillColor(ctx, kc.r, kc.g, kc.b, kc.a);
        CGContextFillRect(ctx, r);
    }

    // Left mini buttons: Play/Pause + Randomize
    CGFloat ctrlW = w * 0.088;
    CGFloat bW = (ctrlW - 6.0) * 0.5;
    CGRect playR = CGRectMake(r.origin.x + 2.0, r.origin.y + 2.0, bW, h - 4.0);
    CGRect rndR  = CGRectMake(r.origin.x + 4.0 + bW, r.origin.y + 2.0, bW, h - 4.0);

    TPDrawRoundedRect(ctx, playR, 4.0);
    CGContextSetRGBFillColor(ctx, _beatPlaying ? 0.10 : 0.14, _beatPlaying ? 0.32 : 0.14, _beatPlaying ? 0.22 : 0.18, 0.95);
    CGContextFillPath(ctx);
    NSString *pSym = _beatPlaying ? @"❚❚" : @"▶";
    CGSize ps = TPMeasureText(pSym, 9.0, NSFontWeightBold, NO);
    TPDrawText(ctx, pSym, CGPointMake(playR.origin.x + (playR.size.width - ps.width) * 0.5, playR.origin.y + (playR.size.height - ps.height) * 0.5),
               9.0, NSFontWeightBold, [NSColor colorWithRed:0.3 green:1.0 blue:0.65 alpha:1.0], NO);

    TPDrawRoundedRect(ctx, rndR, 4.0);
    CGContextSetRGBFillColor(ctx, 0.20, 0.11, 0.28, 0.95);
    CGContextFillPath(ctx);
    NSString *rSym = @"↻";
    CGSize rs = TPMeasureText(rSym, 11.0, NSFontWeightBold, NO);
    TPDrawText(ctx, rSym, CGPointMake(rndR.origin.x + (rndR.size.width - rs.width) * 0.5, rndR.origin.y + (rndR.size.height - rs.height) * 0.5),
               11.0, NSFontWeightBold, [NSColor colorWithRed:1.0 green:0.55 blue:0.95 alpha:1.0], NO);

    // 16 Glowing Step Columns (3 tactile LED rows per step!)
    CGFloat gridX = r.origin.x + ctrlW + 3.0;
    CGFloat gridW = w - ctrlW - 5.0;
    CGFloat colW = gridW / (CGFloat)TP_BEAT_STEPS;
    CGFloat rowH = (h - 6.0) / 3.0;

    for (int s = 0; s < TP_BEAT_STEPS; s++) {
        CGFloat x = gridX + (CGFloat)s * colW + 1.0;
        CGFloat pw = colW - 2.2;
        BOOL isPlayhead = (_beatPlaying && s == ((_beatCurrentStep + TP_BEAT_STEPS - 1) % TP_BEAT_STEPS));
        float glow = _beatStepGlow[s];

        // Bar-beat divider highlight every 4 steps
        if (s % 4 == 0) {
            CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.06);
            CGContextFillRect(ctx, CGRectMake(x - 0.5, r.origin.y + 1.0, pw + 1.0, h - 2.0));
        }

        // Row 0 (Bottom): 808 KICK (Hot Magenta/Red)
        CGRect rKick = CGRectMake(x, r.origin.y + 2.0, pw, rowH - 1.2);
        TPDrawRoundedRect(ctx, rKick, 2.0);
        if (_beatGrid[0][s]) {
            CGContextSetRGBFillColor(ctx, 1.0, 0.16 + glow * 0.5, 0.45 + glow * 0.4, 0.72 + glow * 0.28);
        } else {
            CGContextSetRGBFillColor(ctx, 0.16, 0.10, 0.14, 0.65);
        }
        CGContextFillPath(ctx);

        // Row 1 (Middle): SNARE / HAT (Electric Cyan)
        CGRect rSnare = CGRectMake(x, r.origin.y + 2.0 + rowH, pw, rowH - 1.2);
        TPDrawRoundedRect(ctx, rSnare, 2.0);
        if (_beatGrid[1][s]) {
            CGContextSetRGBFillColor(ctx, 0.05 + glow * 0.6, 0.94, 1.0, 0.78 + glow * 0.22);
        } else if (_beatGrid[2][s]) {
            CGContextSetRGBFillColor(ctx, 0.05, 0.52, 0.68, 0.52 + glow * 0.35);
        } else {
            CGContextSetRGBFillColor(ctx, 0.10, 0.14, 0.18, 0.65);
        }
        CGContextFillPath(ctx);

        // Row 2 (Top): ACID 303 SYNTH (Neon Gold/Lime)
        CGRect rAcid = CGRectMake(x, r.origin.y + 2.0 + rowH * 2.0, pw, rowH - 1.2);
        TPDrawRoundedRect(ctx, rAcid, 2.0);
        if (_beatGrid[3][s]) {
            CGContextSetRGBFillColor(ctx, 0.95, 0.88 + glow * 0.12, 0.15 + glow * 0.6, 0.72 + glow * 0.28);
        } else {
            CGContextSetRGBFillColor(ctx, 0.14, 0.14, 0.10, 0.65);
        }
        CGContextFillPath(ctx);

        // Blazing playhead scanline border
        if (isPlayhead) {
            CGRect ph = CGRectMake(x - 0.5, r.origin.y + 1.0, pw + 1.0, h - 2.0);
            TPDrawRoundedRect(ctx, ph, 3.0);
            CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.95);
            CGContextSetLineWidth(ctx, 1.4);
            CGContextStrokePath(ctx);
        }
    }
}

#pragma mark - Mode 5: Mercury Vortex Physics Sandbox

- (void)stepPhysics:(float)dt {
    BOOL holding = NO;
    float holdX = 0.5f, holdY = 15.0f;
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (_touches[k].active) {
            holding = YES;
            holdX = _touches[k].x;
            holdY = _touches[k].y * 30.0f;
            break;
        }
    }

    if (holding) {
        _vortexCharge = TPClampf(_vortexCharge + dt * 1.6f, 0.0f, 1.8f);
    } else {
        _vortexCharge = MAX(0.0f, _vortexCharge - dt * 3.0f);
    }

    // Step all 78 liquid neon orbs
    for (int i = 0; i < TP_PHYS_ORBS; i++) {
        TPPhysOrb *o = &_orbs[i];

        // Magnetic Vortex suction when holding fingers!
        for (int k = 0; k < TP_MAX_TOUCHES; k++) {
            if (!_touches[k].active) continue;
            float tx = _touches[k].x;
            float ty = _touches[k].y * 30.0f;
            float dx = tx - o->x;
            float dy = (ty - o->y) / 30.0f;
            float distSq = dx * dx + dy * dy + 0.002f;
            float pull = 0.055f / distSq;
            pull = MIN(pull, 4.8f);
            // Pull inward + tangential vortex swirl!
            o->vx += (dx * pull - dy * pull * 0.65f) * dt;
            o->vy += (dy * pull * 30.0f + dx * pull * 32.0f) * dt;
            o->energy = MIN(1.0f, o->energy + dt * 2.5f);
        }

        // Subtle ambient mouse repulsion ripple when not holding
        if (!holding && _mouseReactive) {
            float dx = o->x - _mouseNormX;
            if (fabsf(dx) < 0.07f) {
                o->vx += (dx >= 0 ? 0.5f : -0.5f) * dt;
            }
        }

        o->x += o->vx * dt;
        o->y += o->vy * dt;

        // Gentle damping so orbits stabilize gracefully
        float damp = powf(0.45f, dt);
        o->vx *= damp;
        o->vy *= damp;
        o->energy = MAX(0.25f, o->energy - dt * 0.65f);

        // Keep lively minimum ambient drift
        if (fabsf(o->vx) < 0.025f) o->vx += TPRandRange(-0.04f, 0.04f) * dt;

        // Elastic wall bounces with neon spark energy boost!
        if (o->x < 0.01f) { o->x = 0.01f; o->vx = fabsf(o->vx) * 0.92f; o->energy = 1.0f; }
        if (o->x > 0.99f) { o->x = 0.99f; o->vx = -fabsf(o->vx) * 0.92f; o->energy = 1.0f; }
        if (o->y < o->radius) { o->y = o->radius; o->vy = fabsf(o->vy) * 0.88f; }
        if (o->y > 30.0f - o->radius) { o->y = 30.0f - o->radius; o->vy = -fabsf(o->vy) * 0.88f; }
    }

    // Fast pairwise elastic collisions (gives that juicy liquid-mercury slosh!)
    const float invAspect = 1.0f / 26.0f;
    for (int i = 0; i < TP_PHYS_ORBS; i++) {
        for (int j = i + 1; j < TP_PHYS_ORBS; j++) {
            float dx = _orbs[j].x - _orbs[i].x;
            float minX = (_orbs[i].radius + _orbs[j].radius) * 0.0014f;
            if (fabsf(dx) > minX * 1.4f) continue;
            float dy = (_orbs[j].y - _orbs[i].y) * invAspect;
            float d2 = dx * dx + dy * dy;
            float minD = minX;
            if (d2 > 0.0000001f && d2 < minD * minD) {
                float d = sqrtf(d2);
                float nx = dx / d;
                float ny = dy / d;
                float overlap = (minD - d) * 0.5f;
                _orbs[i].x -= nx * overlap;
                _orbs[j].x += nx * overlap;
                _orbs[i].y -= ny * overlap / invAspect;
                _orbs[j].y += ny * overlap / invAspect;

                float rvx = _orbs[j].vx - _orbs[i].vx;
                float rvy = (_orbs[j].vy - _orbs[i].vy) * invAspect;
                float vn = rvx * nx + rvy * ny;
                if (vn < 0.0f) {
                    float imp = -0.92f * vn;
                    _orbs[i].vx -= imp * nx;
                    _orbs[j].vx += imp * nx;
                    _orbs[i].vy -= (imp * ny) / invAspect;
                    _orbs[j].vy += (imp * ny) / invAspect;
                    _orbs[i].energy = 1.0f;
                    _orbs[j].energy = 1.0f;
                }
            }
        }
    }
    (void)holdX; (void)holdY;
}

- (void)touchPhysicsBegan:(float)nx y:(float)ny {
    float freq = [TPAudioEngine frequencyForScale:_synthScale index:(int)(nx * 16.0f) totalKeys:18];
    [[TPAudioEngine shared] pluckSynthFreq:freq pan:nx * 2.0f - 1.0f velocity:0.32f waveform:0];
}

- (void)touchPhysicsMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy {
    // Bowling-ball shockwave slam when swiping fast!
    float speed = fabsf(vx);
    if (speed > 0.45f) {
        for (int i = 0; i < TP_PHYS_ORBS; i++) {
            float dx = _orbs[i].x - nx;
            if (fabsf(dx) < 0.09f) {
                _orbs[i].vx += vx * 0.55f;
                _orbs[i].vy += TPRandRange(-45.0f, 45.0f);
                _orbs[i].energy = 1.0f;
            }
        }
    }
}

- (void)touchPhysicsEnded:(float)nx y:(float)ny {
    // SLINGSHOT VORTEX EXPLOSION on release!!
    if (_vortexCharge > 0.25f) {
        float power = 0.65f + _vortexCharge * 0.65f;
        for (int i = 0; i < TP_PHYS_ORBS; i++) {
            float dx = _orbs[i].x - nx;
            float dy = _orbs[i].y - ny * 30.0f;
            if (fabsf(dx) < 0.25f) {
                float dir = (dx >= 0.0f ? 1.0f : -1.0f);
                _orbs[i].vx += dir * TPRandRange(0.45f, 1.35f) * power;
                _orbs[i].vy += (dy >= 0.0f ? 1.0f : -1.0f) * TPRandRange(20.0f, 65.0f);
                _orbs[i].energy = 1.0f;
            }
        }
        [[TPAudioEngine shared] playSFX:TPSFXSupernova pan:nx * 2.0f - 1.0f pitchScale:1.4f];
        for (int p = 0; p < 20; p++) {
            float ang = TPRandRange(0, 6.283f);
            [self spawnParticleX:nx y:ny * 30.0f vx:cosf(ang) * 0.35f vy:sinf(ang) * 45.0f
                            life:0.55f size:4.0f hue:TPRandf() kind:1];
        }
    }
}

- (void)renderPhysics:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;

    // Draw electric neon tether webs between fast nearby orbs (gives liquid-mercury glow!)
    CGContextSetLineWidth(ctx, 1.0);
    for (int i = 0; i < TP_PHYS_ORBS; i += 2) {
        for (int j = i + 1; j < MIN(TP_PHYS_ORBS, i + 8); j++) {
            float dx = _orbs[j].x - _orbs[i].x;
            if (fabsf(dx) > 0.048f) continue;
            float alpha = (1.0f - fabsf(dx) / 0.048f) * 0.45f;
            TPRGBA lc = TPThemeColor(_theme, _orbs[i].hue + t * 0.15f, alpha);
            CGContextSetRGBStrokeColor(ctx, lc.r, lc.g, lc.b, lc.a);
            CGContextMoveToPoint(ctx, r.origin.x + _orbs[i].x * w, r.origin.y + _orbs[i].y);
            CGContextAddLineToPoint(ctx, r.origin.x + _orbs[j].x * w, r.origin.y + _orbs[j].y);
            CGContextStrokePath(ctx);
        }
    }

    // Draw swirling vortex rings under active fingers
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        CGFloat cx = r.origin.x + _touches[k].x * w;
        CGFloat cy = r.origin.y + _touches[k].y * h;
        for (int ring = 0; ring < 3; ring++) {
            CGFloat rad = 8.0 + ring * 8.0 + sinf(t * 14.0f - ring) * 3.0;
            TPRGBA rc = TPThemeColor(_theme, fmodf(t * 0.7f + ring * 0.25f, 1.0f), 0.75f - ring * 0.2f);
            CGContextSetRGBStrokeColor(ctx, rc.r, rc.g, rc.b, rc.a);
            CGContextSetLineWidth(ctx, 1.6);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - rad * 1.5, cy - rad * 0.55, rad * 3.0, rad * 1.1));
        }
    }

    // Draw all 78 luminous liquid orbs + velocity comet streaks
    for (int i = 0; i < TP_PHYS_ORBS; i++) {
        TPPhysOrb *o = &_orbs[i];
        CGFloat cx = r.origin.x + o->x * w;
        CGFloat cy = r.origin.y + o->y;
        float spd = fabsf(o->vx);
        TPRGBA col = TPThemeColor(_theme, fmodf(o->hue + t * 0.12f + spd * 0.4f, 1.0f), 0.75f + 0.25f * o->energy);

        if (spd > 0.12f) {
            CGContextSetRGBStrokeColor(ctx, col.r, col.g, col.b, 0.45f);
            CGContextSetLineWidth(ctx, o->radius * 0.9f);
            CGContextMoveToPoint(ctx, cx, cy);
            CGContextAddLineToPoint(ctx, cx - o->vx * w * 0.04f, cy - o->vy * 0.04f);
            CGContextStrokePath(ctx);
        }
        TPDrawGlowCircle(ctx, cx, cy, o->radius * (1.25f + o->energy * 0.55f), col);
    }
}

@end

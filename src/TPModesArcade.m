#import "TPEngine.h"
#import <math.h>

@implementation TPEngine (ArcadeModes)

#pragma mark - Mode 2: Cyber Runner (Endless Touch Bar Arcade)

- (void)resetRunner {
    _runnerGameOver = NO;
    _runnerY = 0.0f;
    _runnerVY = 0.0f;
    _runnerJumpsLeft = 2;
    _runnerSpeed = 245.0f;
    _runnerScore = 0.0f;
    _runnerDist = 0.0f;
    _runnerLegPhase = 0.0f;
    _runnerSpawnTimer = 0.85f;
    _runnerFlash = 0.0f;
    memset(_obstacles, 0, sizeof(_obstacles));
}

- (void)stepRunner:(float)dt {
    if (_runnerFlash > 0.0f) {
        _runnerFlash = MAX(0.0f, _runnerFlash - dt * 3.0f);
    }
    if (_runnerGameOver) return;

    _runnerSpeed = MIN(520.0f, _runnerSpeed + dt * 7.5f);
    _runnerDist += _runnerSpeed * dt;
    _runnerScore += dt * 14.0f;
    _runnerLegPhase += dt * (_runnerSpeed * 0.075f);

    // Runner jump & gravity physics (tuned crisply for 30pt vertical space!)
    if (_runnerY > 0.0f || _runnerVY != 0.0f) {
        _runnerVY -= 285.0f * dt;
        _runnerY += _runnerVY * dt;
        if (_runnerY <= 0.0f) {
            _runnerY = 0.0f;
            _runnerVY = 0.0f;
            _runnerJumpsLeft = 2;
        }
        if (_runnerY > 17.5f) {
            _runnerY = 17.5f;
            if (_runnerVY > 0.0f) _runnerVY = 0.0f;
        }
    }

    // Spawn obstacles & gold energy orbs
    _runnerSpawnTimer -= dt;
    if (_runnerSpawnTimer <= 0.0f) {
        for (int i = 0; i < TP_MAX_OBSTACLES; i++) {
            if (!_obstacles[i].active) {
                TPRunnerObstacle *ob = &_obstacles[i];
                ob->active = YES;
                ob->collected = NO;
                ob->x = 920.0f;
                ob->phase = TPRandRange(0.0f, 6.28f);
                float r = TPRandf();
                if (r < 0.42f) {
                    // Ground neon spike
                    ob->kind = 0;
                    ob->width = 11.0f;
                    ob->height = TPRandRange(9.0f, 12.5f);
                    ob->yBase = 3.0f;
                } else if (r < 0.68f) {
                    // Double laser barrier
                    ob->kind = 1;
                    ob->width = 18.0f;
                    ob->height = 10.0f;
                    ob->yBase = 3.0f;
                } else if (r < 0.84f) {
                    // Hovering cyber-drone (stay low or jump over!)
                    ob->kind = 2;
                    ob->width = 15.0f;
                    ob->height = 6.5f;
                    ob->yBase = 15.5f;
                } else {
                    // Collectible spinning gold energy diamond!
                    ob->kind = 3;
                    ob->width = 9.0f;
                    ob->height = 9.0f;
                    ob->yBase = TPRandf() < 0.5f ? 14.0f : 6.0f;
                }
                break;
            }
        }
        float minGap = MAX(0.55f, 1.38f - (_runnerSpeed - 245.0f) * 0.0021f);
        _runnerSpawnTimer = TPRandRange(minGap, minGap + 0.52f);
    }

    // Update obstacles & check collisions
    const float playerX = 68.0f;
    const float playerW = 10.0f;
    const float playerH = 10.5f;
    const float playerBottom = 3.0f + _runnerY;

    for (int i = 0; i < TP_MAX_OBSTACLES; i++) {
        TPRunnerObstacle *ob = &_obstacles[i];
        if (!ob->active) continue;
        ob->x -= _runnerSpeed * dt * (ob->kind == 2 ? 1.12f : 1.0f);
        if (ob->x < -30.0f) {
            ob->active = NO;
            continue;
        }

        float obY = ob->yBase + (ob->kind == 2 ? sinf((float)_time * 8.0f + ob->phase) * 2.0f : 0.0f);

        // Forgiving hitbox for fun arcade feel
        BOOL overlapX = (playerX + playerW - 2.0f > ob->x + 1.5f) && (playerX + 2.0f < ob->x + ob->width - 1.5f);
        BOOL overlapY = (playerBottom + playerH - 1.5f > obY + 1.0f) && (playerBottom + 1.5f < obY + ob->height - 1.0f);

        if (overlapX && overlapY) {
            if (ob->kind == 3 && !ob->collected) {
                ob->collected = YES;
                ob->active = NO;
                _runnerScore += 35.0f;
                [[TPAudioEngine shared] playSFX:TPSFXCoin pan:-0.55f pitchScale:1.1f];
                for (int k = 0; k < 10; k++) {
                    [self spawnParticleX:(playerX / 900.0f)
                                       y:playerBottom + 6.0f
                                      vx:TPRandRange(-0.12f, 0.16f)
                                      vy:TPRandRange(-20.0f, 32.0f)
                                    life:0.45f
                                    size:3.2f
                                     hue:0.16f
                                    kind:0];
                }
            } else if (ob->kind != 3) {
                // Crash!
                _runnerGameOver = YES;
                _runnerFlash = 1.0f;
                int finalScore = (int)_runnerScore;
                if (finalScore > _runnerHighScore) {
                    _runnerHighScore = finalScore;
                    [[NSUserDefaults standardUserDefaults] setInteger:_runnerHighScore forKey:@"TouchPulseRunnerHigh"];
                }
                [[TPAudioEngine shared] playSFX:TPSFXExplosion pan:-0.5f pitchScale:1.0f];
                for (int k = 0; k < 28; k++) {
                    [self spawnParticleX:(playerX / 900.0f)
                                       y:playerBottom + 5.0f
                                      vx:TPRandRange(-0.22f, 0.25f)
                                      vy:TPRandRange(8.0f, 52.0f)
                                    life:TPRandRange(0.45f, 0.95f)
                                    size:TPRandRange(2.2f, 4.5f)
                                     hue:TPRandf()
                                    kind:3];
                }
                break;
            }
        }
    }
}

- (void)touchRunnerBegan:(float)nx y:(float)ny {
    if (_runnerGameOver) {
        [self resetRunner];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:1.3f];
        return;
    }

    if (_runnerJumpsLeft > 0) {
        BOOL isDouble = (_runnerJumpsLeft == 1);
        _runnerVY = isDouble ? 102.0f : 112.0f;
        _runnerJumpsLeft--;
        [[TPAudioEngine shared] playSFX:(isDouble ? TPSFXDoubleJump : TPSFXJump) pan:-0.6f pitchScale:1.0f];

        // Jetpack / jump burst particles!
        for (int i = 0; i < (isDouble ? 12 : 6); i++) {
            [self spawnParticleX:(68.0f / 900.0f)
                               y:3.0f + _runnerY
                              vx:TPRandRange(-0.14f, -0.02f)
                              vy:TPRandRange(-28.0f, -4.0f)
                            life:TPRandRange(0.22f, 0.45f)
                            size:isDouble ? 3.8f : 2.8f
                             hue:isDouble ? 0.55f : 0.08f
                            kind:0];
        }
    }
}

- (void)renderRunner:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat scaleX = w / 900.0;

    // 1. Scrolling synthwave starfield & distant neon skyline
    for (int i = 0; i < 18; i++) {
        float sx = fmodf(((float)i * 67.0f - _runnerDist * 0.06f), 900.0f);
        if (sx < 0) sx += 900.0f;
        float sy = 14.0f + fmodf((float)i * 7.3f, 13.0f);
        CGContextSetRGBFillColor(ctx, 0.7, 0.85, 1.0, 0.42);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + sx * scaleX, r.origin.y + sy, 1.4, 1.4));
    }

    // Parallax wireframe skyline silhouette
    TPRGBA skyC = TPThemeColor(_theme, 0.35f, 0.22f);
    CGContextSetRGBStrokeColor(ctx, skyC.r, skyC.g, skyC.b, skyC.a);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextBeginPath(ctx);
    for (int i = 0; i <= 30; i++) {
        float bx = (float)i * 32.0f - fmodf(_runnerDist * 0.22f, 32.0f);
        int idx = (int)floorf((_runnerDist * 0.22f + bx) / 32.0f);
        float bh = 5.0f + (float)((idx * 17) % 11);
        CGFloat x0 = r.origin.x + bx * scaleX;
        if (i == 0) CGContextMoveToPoint(ctx, x0, r.origin.y + 3.0);
        CGContextAddLineToPoint(ctx, x0, r.origin.y + 3.0 + bh);
        CGContextAddLineToPoint(ctx, x0 + 28.0 * scaleX, r.origin.y + 3.0 + bh);
        CGContextAddLineToPoint(ctx, x0 + 28.0 * scaleX, r.origin.y + 3.0);
    }
    CGContextStrokePath(ctx);

    // 2. Neon ground rail with scrolling dashes
    TPRGBA railC = TPThemeColor(_theme, 0.05f, 0.92f);
    CGContextSetRGBFillColor(ctx, railC.r, railC.g, railC.b, railC.a);
    CGContextFillRect(ctx, CGRectMake(r.origin.x, r.origin.y + 2.0, w, 1.5));
    float dashOffset = fmodf(_runnerDist, 36.0f);
    CGContextSetRGBFillColor(ctx, railC.r, railC.g, railC.b, 0.45f);
    for (float dx = -dashOffset; dx < 900.0f; dx += 36.0f) {
        CGContextFillRect(ctx, CGRectMake(r.origin.x + dx * scaleX, r.origin.y, 14.0 * scaleX, 1.5));
    }

    // 3. Obstacles & collectibles
    for (int i = 0; i < TP_MAX_OBSTACLES; i++) {
        TPRunnerObstacle *ob = &_obstacles[i];
        if (!ob->active) continue;
        CGFloat ox = r.origin.x + ob->x * scaleX;
        CGFloat ow = ob->width * scaleX;
        CGFloat oy = r.origin.y + ob->yBase + (ob->kind == 2 ? sinf((float)_time * 8.0f + ob->phase) * 2.0 : 0.0);

        if (ob->kind == 0) {
            // Blazing neon spike triangle
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, ox, oy);
            CGContextAddLineToPoint(ctx, ox + ow * 0.5, oy + ob->height);
            CGContextAddLineToPoint(ctx, ox + ow, oy);
            CGContextClosePath(ctx);
            CGContextSetRGBFillColor(ctx, 1.0, 0.16, 0.44, 0.95);
            CGContextFillPath(ctx);
            CGContextSetRGBStrokeColor(ctx, 1.0, 0.72, 0.85, 0.9);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextStrokePath(ctx);
        } else if (ob->kind == 1) {
            // Double neon plasma pylons
            CGFloat pw = ow * 0.36;
            CGContextSetRGBFillColor(ctx, 1.0, 0.25, 0.30, 0.95);
            TPDrawRoundedRect(ctx, CGRectMake(ox, oy, pw, ob->height), 1.5);
            CGContextFillPath(ctx);
            TPDrawRoundedRect(ctx, CGRectMake(ox + ow - pw, oy, pw, ob->height * 0.85), 1.5);
            CGContextFillPath(ctx);
            // Crackling laser beam connecting pylons
            CGContextSetRGBStrokeColor(ctx, 1.0, 0.85, 0.9, 0.9);
            CGContextSetLineWidth(ctx, 1.2);
            CGContextMoveToPoint(ctx, ox + pw * 0.5, oy + ob->height * 0.7);
            CGContextAddLineToPoint(ctx, ox + ow - pw * 0.5, oy + ob->height * 0.65);
            CGContextStrokePath(ctx);
        } else if (ob->kind == 2) {
            // Hovering cyber-drone with glowing red eye
            TPDrawRoundedRect(ctx, CGRectMake(ox, oy, ow, ob->height), 3.0);
            CGContextSetRGBFillColor(ctx, 0.95, 0.15, 0.28, 0.95);
            CGContextFillPath(ctx);
            TPDrawGlowCircle(ctx, ox + ow * 0.25, oy + ob->height * 0.5, 4.5, (TPRGBA){1.0f, 0.78f, 0.2f, 0.95f});
        } else if (ob->kind == 3) {
            // Spinning gold energy diamond
            CGFloat cx = ox + ow * 0.5;
            CGFloat cy = oy + ob->height * 0.5;
            CGFloat pulse = 4.5 + sinf((float)_time * 10.0f) * 1.2;
            TPDrawGlowCircle(ctx, cx, cy, pulse + 3.0, (TPRGBA){1.0f, 0.85f, 0.15f, 0.9f});
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, cx, cy + 4.5);
            CGContextAddLineToPoint(ctx, cx + 4.0, cy);
            CGContextAddLineToPoint(ctx, cx, cy - 4.5);
            CGContextAddLineToPoint(ctx, cx - 4.0, cy);
            CGContextClosePath(ctx);
            CGContextSetRGBFillColor(ctx, 1.0, 0.96, 0.65, 1.0);
            CGContextFillPath(ctx);
        }
    }

    // 4. The Cyber Runner character (glowing neon dino/cyberbot!)
    if (!_runnerGameOver) {
        CGFloat px = r.origin.x + 68.0 * scaleX;
        CGFloat py = r.origin.y + 3.5 + _runnerY;
        TPRGBA pc = TPThemeColor(_theme, 0.0f, 1.0f);

        // Jetpack trail glow when airborne
        if (_runnerY > 1.0f) {
            TPDrawGlowCircle(ctx, px - 2.0, py + 2.0, 6.5, (TPRGBA){0.0f, 0.95f, 1.0f, 0.85f});
        }

        // Body & Dino/Runner silhouette
        TPDrawRoundedRect(ctx, CGRectMake(px, py + 2.5, 8.5, 6.0), 2.0);
        CGContextSetRGBFillColor(ctx, pc.r, pc.g, pc.b, 1.0);
        CGContextFillPath(ctx);

        // Head
        TPDrawRoundedRect(ctx, CGRectMake(px + 3.5, py + 7.2, 7.5, 4.8), 1.8);
        CGContextSetRGBFillColor(ctx, TPLerpf(pc.r, 1.0f, 0.25f), TPLerpf(pc.g, 1.0f, 0.25f), TPLerpf(pc.b, 1.0f, 0.25f), 1.0);
        CGContextFillPath(ctx);

        // Glowing white visor eye
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(px + 7.5, py + 9.2, 2.8, 1.5));

        // Tail
        CGContextSetRGBFillColor(ctx, pc.r, pc.g, pc.b, 0.9);
        CGContextFillRect(ctx, CGRectMake(px - 3.2, py + 4.5, 3.6, 2.2));

        // Animated running legs
        float step = (_runnerY > 1.0f) ? 1.5f : sinf(_runnerLegPhase) * 2.5f;
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.95);
        CGContextFillRect(ctx, CGRectMake(px + 1.5 + step, py, 2.2, 3.0));
        CGContextFillRect(ctx, CGRectMake(px + 5.2 - step, py, 2.2, 3.0));
    }

    // 5. Score & High Score HUD on right
    NSString *scoreTxt = [NSString stringWithFormat:@"%04d  HI %04d", (int)_runnerScore, MAX(_runnerHighScore, (int)_runnerScore)];
    CGSize ss = TPMeasureText(scoreTxt, 10.5, NSFontWeightBold, YES);
    TPDrawText(ctx, scoreTxt,
               CGPointMake(r.origin.x + w - ss.width - 8.0, r.origin.y + h - ss.height - 3.0),
               10.5, NSFontWeightBold, [NSColor colorWithWhite:0.95 alpha:0.92], YES);

    // Crash flash & Game Over overlay
    if (_runnerFlash > 0.01f) {
        CGContextSetRGBFillColor(ctx, 1.0, 0.15, 0.25, _runnerFlash * 0.45);
        CGContextFillRect(ctx, r);
    }

    if (_runnerGameOver) {
        NSString *go = [NSString stringWithFormat:@"GAME OVER • SCORE %d • TAP TO RETRY", (int)_runnerScore];
        CGSize gs = TPMeasureText(go, 11.0, NSFontWeightBold, NO);
        CGRect box = CGRectMake(r.origin.x + (w - gs.width - 20.0) * 0.5, r.origin.y + 4.0, gs.width + 20.0, h - 8.0);
        TPDrawRoundedRect(ctx, box, 8.0);
        CGContextSetRGBFillColor(ctx, 0.08, 0.04, 0.08, 0.88);
        CGContextFillPath(ctx);
        TPDrawRoundedRect(ctx, CGRectInset(box, 0.5, 0.5), 7.5);
        CGContextSetRGBStrokeColor(ctx, 1.0, 0.25, 0.45, 0.95);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokePath(ctx);
        TPDrawText(ctx, go,
                   CGPointMake(box.origin.x + 10.0, box.origin.y + (box.size.height - gs.height) * 0.5),
                   11.0, NSFontWeightBold, [NSColor whiteColor], NO);
    }
}

#pragma mark - Mode 3: Laser Blaster (Multi-Touch Arcade Zapper!)

- (void)resetBlaster {
    _blasterGameOver = NO;
    _blasterScore = 0;
    _blasterCombo = 0;
    _blasterMaxCombo = 0;
    _blasterShield = 5;
    _blasterOverdrive = 0.0f;
    _blasterSpawnTimer = 0.5f;
    _blasterShake = 0.0f;
    memset(_targets, 0, sizeof(_targets));
    memset(_bolts, 0, sizeof(_bolts));
}

- (void)stepBlaster:(float)dt {
    if (_blasterShake > 0.0f) _blasterShake = MAX(0.0f, _blasterShake - dt * 4.5f);
    if (_blasterOverdrive > 0.0f) _blasterOverdrive = MAX(0.0f, _blasterOverdrive - dt);

    // Decay laser bolts
    for (int i = 0; i < TP_MAX_BOLTS; i++) {
        if (!_bolts[i].active) continue;
        _bolts[i].life -= dt * 4.2f;
        if (_bolts[i].life <= 0.0f) _bolts[i].active = NO;
    }

    if (_blasterGameOver) return;

    // Spawn neon targets across the wide Touch Bar (leaving right 105pt clear for HUD)
    _blasterSpawnTimer -= dt;
    if (_blasterSpawnTimer <= 0.0f) {
        for (int i = 0; i < TP_MAX_TARGETS; i++) {
            if (!_targets[i].active) {
                TPBlasterTarget *tg = &_targets[i];
                tg->active = YES;
                tg->x = TPRandRange(0.05f, 0.80f);
                tg->y = TPRandRange(8.5f, 21.5f);
                float r = TPRandf();
                if (r < 0.18f) {
                    tg->kind = 2; // Bonus golden star!
                    tg->vx = TPRandRange(-0.06f, 0.06f);
                    tg->lifetime = 2.6f;
                    tg->hue = 0.14f;
                } else if (r < 0.45f) {
                    tg->kind = 1; // Drifting comet
                    tg->vx = (TPRandf() < 0.5f ? -1.0f : 1.0f) * TPRandRange(0.05f, 0.11f);
                    tg->lifetime = MAX(1.9f, 3.1f - _blasterScore * 0.0006f);
                    tg->hue = TPRandf();
                } else {
                    tg->kind = 0; // Stationary pulsing energy orb
                    tg->vx = 0.0f;
                    tg->lifetime = MAX(1.8f, 3.2f - _blasterScore * 0.0006f);
                    tg->hue = TPRandf();
                }
                tg->age = 0.0f;
                break;
            }
        }
        float rate = MAX(0.36f, 1.12f - (float)_blasterScore * 0.00035f);
        _blasterSpawnTimer = TPRandRange(rate * 0.7f, rate * 1.2f);
    }

    for (int i = 0; i < TP_MAX_TARGETS; i++) {
        TPBlasterTarget *tg = &_targets[i];
        if (!tg->active) continue;
        tg->age += dt;
        tg->x += tg->vx * dt;
        if (tg->x < 0.04f || tg->x > 0.81f) {
            tg->vx = -tg->vx;
            tg->x = TPClampf(tg->x, 0.04f, 0.81f);
        }

        if (tg->age >= tg->lifetime) {
            tg->active = NO;
            if (tg->kind != 2) {
                // Missed a meteor -> shield hit!
                _blasterCombo = 0;
                _blasterShield--;
                _blasterShake = 1.0f;
                [[TPAudioEngine shared] playSFX:TPSFXExplosion pan:tg->x * 2.0f - 1.0f pitchScale:0.7f];
                if (_blasterShield <= 0) {
                    _blasterGameOver = YES;
                    if (_blasterScore > _blasterHighScore) {
                        _blasterHighScore = _blasterScore;
                        [[NSUserDefaults standardUserDefaults] setInteger:_blasterHighScore forKey:@"TouchPulseBlasterHigh"];
                    }
                }
            }
        }
    }
}

- (void)touchBlasterBegan:(float)nx y:(float)ny {
    if (_blasterGameOver) {
        [self resetBlaster];
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:1.3f];
        return;
    }

    // Find closest target near tapped X
    int best = -1;
    float bestDist = 0.068f; // generous multi-touch tap radius across the bar!
    for (int i = 0; i < TP_MAX_TARGETS; i++) {
        if (!_targets[i].active) continue;
        float d = fabsf(_targets[i].x - nx);
        if (d < bestDist) {
            bestDist = d;
            best = i;
        }
    }

    if (best >= 0) {
        TPBlasterTarget *tg = &_targets[best];
        float tx = tg->x;
        float ty = tg->y;
        float hue = tg->hue;
        int kind = tg->kind;
        tg->active = NO;

        _blasterCombo++;
        if (_blasterCombo > _blasterMaxCombo) _blasterMaxCombo = _blasterCombo;
        if (_blasterCombo > 0 && (_blasterCombo % 10 == 0)) {
            _blasterOverdrive = 6.0f;
            if (_blasterShield < 5) _blasterShield++;
            [self showToast:@"OVERDRIVE 2X!" subtitle:@"Shield Restored!"];
        }

        int mult = (_blasterOverdrive > 0.0f ? 2 : 1) * (1 + _blasterCombo / 5);
        _blasterScore += (kind == 2 ? 50 : 15) * mult;

        // Spawn crackling lightning bolt from bottom emitter to target
        for (int b = 0; b < TP_MAX_BOLTS; b++) {
            if (!_bolts[b].active) {
                _bolts[b].active = YES;
                _bolts[b].x0 = TPClampf(nx + TPRandRange(-0.04f, 0.04f), 0.02f, 0.96f);
                _bolts[b].y0 = 0.0f;
                _bolts[b].x1 = tx;
                _bolts[b].y1 = ty;
                _bolts[b].life = 1.0f;
                _bolts[b].hue = hue;
                break;
            }
        }

        // Musical ascending pentatonic laser zap + chime!
        float noteFreq = [TPAudioEngine frequencyForScale:TPSynthScalePentatonic
                                                    index:(_blasterCombo % 14) + 3
                                                totalKeys:18];
        [[TPAudioEngine shared] playSFX:TPSFXLaserZap pan:tx * 2.0f - 1.0f pitchScale:0.85f + 0.05f * (_blasterCombo % 10)];
        [[TPAudioEngine shared] pluckSynthFreq:noteFreq pan:tx * 2.0f - 1.0f velocity:0.35f waveform:0];

        // Shattering spark burst!
        for (int p = 0; p < 18; p++) {
            float ang = TPRandRange(0.0f, 6.283f);
            float spd = TPRandRange(0.07f, 0.28f);
            [self spawnParticleX:tx
                               y:ty
                              vx:cosf(ang) * spd
                              vy:sinf(ang) * 42.0f
                            life:TPRandRange(0.28f, 0.65f)
                            size:TPRandRange(2.5f, 5.5f)
                             hue:fmodf(hue + TPRandRange(-0.1f, 0.1f), 1.0f)
                            kind:(p % 2 == 0) ? 1 : 0];
        }
    } else {
        // Missed shot laser puff
        for (int b = 0; b < TP_MAX_BOLTS; b++) {
            if (!_bolts[b].active) {
                _bolts[b].active = YES;
                _bolts[b].x0 = nx;
                _bolts[b].y0 = 0.0f;
                _bolts[b].x1 = nx;
                _bolts[b].y1 = ny * 30.0f;
                _bolts[b].life = 0.55f;
                _bolts[b].hue = 0.6f;
                break;
            }
        }
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:nx * 2.0f - 1.0f pitchScale:0.65f];
    }
}

- (void)renderBlaster:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;

    // Overdrive neon border pulse
    if (_blasterOverdrive > 0.0f) {
        TPRGBA oc = TPThemeColor(_theme, fmodf(t * 2.2f, 1.0f), 0.78f);
        CGContextSetRGBStrokeColor(ctx, oc.r, oc.g, oc.b, oc.a);
        CGContextSetLineWidth(ctx, 2.2);
        CGContextStrokeRect(ctx, CGRectInset(r, 1.0, 1.0));
    }

    // Subtle radar sweep grid
    CGContextSetRGBStrokeColor(ctx, 0.18, 0.30, 0.42, 0.25);
    CGContextSetLineWidth(ctx, 0.8);
    CGContextMoveToPoint(ctx, r.origin.x, r.origin.y + h * 0.5);
    CGContextAddLineToPoint(ctx, r.origin.x + w * 0.84, r.origin.y + h * 0.5);
    CGContextStrokePath(ctx);

    // Render targets with shrinking lock-on timer rings!
    for (int i = 0; i < TP_MAX_TARGETS; i++) {
        TPBlasterTarget *tg = &_targets[i];
        if (!tg->active) continue;
        float progress = TPClampf(tg->age / MAX(0.01f, tg->lifetime), 0.0f, 1.0f);
        CGFloat cx = r.origin.x + tg->x * w;
        CGFloat cy = r.origin.y + tg->y;

        TPRGBA col = (tg->kind == 2)
            ? (TPRGBA){1.0f, 0.88f, 0.18f, 1.0f}
            : TPThemeColor(_theme, tg->hue, 1.0f);

        // Urgent red tint as timer nears expiry
        if (progress > 0.72f && tg->kind != 2) {
            float u = (progress - 0.72f) / 0.28f;
            col.r = TPLerpf(col.r, 1.0f, u);
            col.g = TPLerpf(col.g, 0.1f, u);
            col.b = TPLerpf(col.b, 0.15f, u);
        }

        // Shrinking outer target lock ring
        CGFloat ringR = 13.5 - progress * 8.5;
        CGContextSetRGBStrokeColor(ctx, col.r, col.g, col.b, 0.45 + 0.5 * progress);
        CGContextSetLineWidth(ctx, 1.3);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - ringR, cy - ringR, ringR * 2.0, ringR * 2.0));

        // Glowing core orb
        TPDrawGlowCircle(ctx, cx, cy, tg->kind == 2 ? 8.5 : 7.0, col);
    }

    // Render crackling laser bolts
    for (int b = 0; b < TP_MAX_BOLTS; b++) {
        TPLaserBolt *lb = &_bolts[b];
        if (!lb->active) continue;
        CGFloat x0 = r.origin.x + lb->x0 * w;
        CGFloat y0 = r.origin.y + lb->y0;
        CGFloat x1 = r.origin.x + lb->x1 * w;
        CGFloat y1 = r.origin.y + lb->y1;
        TPRGBA bc = TPThemeColor(_theme, lb->hue, lb->life);

        CGContextSetRGBStrokeColor(ctx, bc.r, bc.g, bc.b, lb->life * 0.75);
        CGContextSetLineWidth(ctx, 4.0 * lb->life);
        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddLineToPoint(ctx, (x0 + x1) * 0.5 + TPRandRange(-4, 4), (y0 + y1) * 0.5);
        CGContextAddLineToPoint(ctx, x1, y1);
        CGContextStrokePath(ctx);

        CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, lb->life);
        CGContextSetLineWidth(ctx, 1.3);
        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddLineToPoint(ctx, x1, y1);
        CGContextStrokePath(ctx);
    }

    // Right-side compact HUD (Score, Combo, Shields)
    CGFloat hudX = r.origin.x + w - 102.0;
    CGRect hudBg = CGRectMake(hudX, r.origin.y + 2.0, 99.0, h - 4.0);
    TPDrawRoundedRect(ctx, hudBg, 6.0);
    CGContextSetRGBFillColor(ctx, 0.06, 0.07, 0.11, 0.88);
    CGContextFillPath(ctx);

    NSString *sc = [NSString stringWithFormat:@"%05d", _blasterScore];
    TPDrawText(ctx, sc, CGPointMake(hudX + 7.0, r.origin.y + 13.5), 10.5, NSFontWeightBold, [NSColor whiteColor], YES);

    if (_blasterCombo >= 2) {
        NSString *cb = [NSString stringWithFormat:@"x%d", _blasterCombo];
        NSColor *cbc = (_blasterOverdrive > 0) ? [NSColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0]
                                               : TPThemeNSColor(_theme, 0.1f, 1.0f);
        TPDrawText(ctx, cb, CGPointMake(hudX + 58.0, r.origin.y + 13.5), 10.5, NSFontWeightHeavy, cbc, YES);
    }

    // 5 crisp shield energy pips
    for (int s = 0; s < 5; s++) {
        CGRect pip = CGRectMake(hudX + 7.0 + s * 17.0, r.origin.y + 5.0, 13.0, 4.5);
        TPDrawRoundedRect(ctx, pip, 2.0);
        if (s < _blasterShield) {
            CGContextSetRGBFillColor(ctx, 0.15, 0.95, 0.62, 0.95);
        } else {
            CGContextSetRGBFillColor(ctx, 0.25, 0.15, 0.18, 0.55);
        }
        CGContextFillPath(ctx);
    }

    if (_blasterShake > 0.01f) {
        CGContextSetRGBFillColor(ctx, 1.0, 0.12, 0.22, _blasterShake * 0.42);
        CGContextFillRect(ctx, r);
    }

    if (_blasterGameOver) {
        NSString *go = [NSString stringWithFormat:@"SHIELDS DOWN • SCORE %d • BEST %d • TAP RETRY",
                        _blasterScore, MAX(_blasterHighScore, _blasterScore)];
        CGSize gs = TPMeasureText(go, 10.5, NSFontWeightBold, NO);
        CGRect box = CGRectMake(r.origin.x + (w - gs.width - 20.0) * 0.5, r.origin.y + 4.0, gs.width + 20.0, h - 8.0);
        TPDrawRoundedRect(ctx, box, 8.0);
        CGContextSetRGBFillColor(ctx, 0.08, 0.04, 0.09, 0.92);
        CGContextFillPath(ctx);
        TPDrawRoundedRect(ctx, CGRectInset(box, 0.5, 0.5), 7.5);
        CGContextSetRGBStrokeColor(ctx, 1.0, 0.28, 0.52, 0.95);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokePath(ctx);
        TPDrawText(ctx, go,
                   CGPointMake(box.origin.x + 10.0, box.origin.y + (box.size.height - gs.height) * 0.5),
                   10.5, NSFontWeightBold, [NSColor whiteColor], NO);
    }
}

#pragma mark - Mode 4: Neon Laser Harp & Polyphonic Ribbon Synth

- (void)stepSynth:(float)dt {
    for (int i = 0; i < TP_SYNTH_KEYS; i++) {
        if (_synthAmp[i] > 0.001f) {
            _synthPhase[i] += dt * (46.0f + (float)i * 3.8f);
            _synthAmp[i] *= powf(0.06f, dt); // smooth musical string decay
        } else {
            _synthAmp[i] = 0.0f;
        }
        _synthGlow[i] = MAX(0.0f, _synthGlow[i] - dt * 1.65f);
    }
}

- (void)touchSynthAt:(TPActiveTouch *)touch isNew:(BOOL)isNew {
    int keyIdx = (int)TPClampf(touch->x * (float)TP_SYNTH_KEYS, 0, TP_SYNTH_KEYS - 1);
    if (!isNew && keyIdx == touch->lastStringIndex) {
        // Gentle sustain shimmer while finger rests on string
        _synthGlow[keyIdx] = MAX(_synthGlow[keyIdx], 0.55f);
        return;
    }

    touch->lastStringIndex = keyIdx;
    _synthAmp[keyIdx] = 1.0f;
    _synthGlow[keyIdx] = 1.0f;

    float freq = [TPAudioEngine frequencyForScale:_synthScale index:keyIdx totalKeys:TP_SYNTH_KEYS];
    float pan = ((float)keyIdx / (float)(TP_SYNTH_KEYS - 1)) * 2.0f - 1.0f;
    float vel = 0.65f + 0.35f * touch->y;
    [[TPAudioEngine shared] pluckSynthFreq:freq pan:pan velocity:vel waveform:0];

    // Burst glowing harp sparks along the plucked string!
    float strNormX = ((float)keyIdx + 0.5f) / (float)TP_SYNTH_KEYS;
    float hue = (float)keyIdx / (float)TP_SYNTH_KEYS;
    for (int p = 0; p < 10; p++) {
        [self spawnParticleX:strNormX
                           y:touch->y * 28.0f
                          vx:TPRandRange(-0.07f, 0.07f)
                          vy:TPRandRange(-28.0f, 28.0f)
                        life:TPRandRange(0.25f, 0.62f)
                        size:TPRandRange(2.5f, 5.2f)
                         hue:hue
                        kind:0];
    }
}

- (void)renderSynth:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat keyW = w / (CGFloat)TP_SYNTH_KEYS;

    // 1. Live Real-Time Output Oscilloscope rippling across OLED backdrop!
    float wave[TP_WAVEFORM_SAMPLES];
    [[TPAudioEngine shared] copyOutputWaveform:wave count:TP_WAVEFORM_SAMPLES];

    CGContextBeginPath(ctx);
    for (int i = 0; i < TP_WAVEFORM_SAMPLES; i++) {
        CGFloat x = r.origin.x + ((CGFloat)i / (CGFloat)(TP_WAVEFORM_SAMPLES - 1)) * w;
        CGFloat y = r.origin.y + h * 0.5 + wave[i] * (h * 0.65);
        if (i == 0) CGContextMoveToPoint(ctx, x, y);
        else CGContextAddLineToPoint(ctx, x, y);
    }
    TPRGBA wc = TPThemeColor(_theme, fmodf((float)_time * 0.15f, 1.0f), 0.42f);
    CGContextSetRGBStrokeColor(ctx, wc.r, wc.g, wc.b, wc.a);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokePath(ctx);

    // 2. Render 18 glowing, physically vibrating Neon Laser Harp Strings!
    for (int i = 0; i < TP_SYNTH_KEYS; i++) {
        float normI = (float)i / (float)(TP_SYNTH_KEYS - 1);
        CGFloat x0 = r.origin.x + (CGFloat)i * keyW;
        CGFloat cx = x0 + keyW * 0.5;
        TPRGBA col = TPThemeColor(_theme, normI * 0.9f, 1.0f);

        // Glowing key pad fill when plucked
        float glow = _synthGlow[i];
        CGRect keyR = CGRectMake(x0 + 1.2, r.origin.y + 1.5, keyW - 2.4, h - 3.0);
        TPDrawRoundedRect(ctx, keyR, 4.0);
        CGContextSetRGBFillColor(ctx, col.r, col.g, col.b, 0.08 + glow * 0.36);
        CGContextFillPath(ctx);

        // Subtle key top/bottom LED accents
        CGContextSetRGBFillColor(ctx, col.r, col.g, col.b, 0.45 + glow * 0.55);
        CGContextFillRect(ctx, CGRectMake(x0 + 3.0, r.origin.y + 1.0, keyW - 6.0, 1.6));
        CGContextFillRect(ctx, CGRectMake(x0 + 3.0, r.origin.y + h - 2.6, keyW - 6.0, 1.6));

        // Physically vibrating standing-wave laser string!
        float amp = _synthAmp[i] * 7.5f;
        float ph = _synthPhase[i];

        for (int pass = 0; pass < 2; pass++) {
            CGContextBeginPath(ctx);
            for (int seg = 0; seg <= 10; seg++) {
                float f = (float)seg / 10.0f;
                float disp = sinf(f * (float)M_PI) * sinf(ph) * amp;
                CGFloat sx = cx + disp;
                CGFloat sy = r.origin.y + 2.0 + f * (h - 4.0);
                if (seg == 0) CGContextMoveToPoint(ctx, sx, sy);
                else CGContextAddLineToPoint(ctx, sx, sy);
            }
            if (pass == 0) {
                CGContextSetRGBStrokeColor(ctx, col.r, col.g, col.b, 0.35 + glow * 0.55);
                CGContextSetLineWidth(ctx, 3.6 + glow * 3.5);
            } else {
                CGContextSetRGBStrokeColor(ctx,
                                           TPLerpf(col.r, 1.0f, 0.45f + glow * 0.5f),
                                           TPLerpf(col.g, 1.0f, 0.45f + glow * 0.5f),
                                           TPLerpf(col.b, 1.0f, 0.45f + glow * 0.5f),
                                           0.85 + glow * 0.15);
                CGContextSetLineWidth(ctx, 1.3);
            }
            CGContextStrokePath(ctx);
        }

        // Crisp subtle note label on alternate or bright keys
        if (keyW >= 28.0 || glow > 0.2f) {
            NSString *note = [TPAudioEngine noteNameForScale:_synthScale index:i];
            CGSize ns = TPMeasureText(note, 7.5, NSFontWeightSemibold, YES);
            TPDrawText(ctx, note,
                       CGPointMake(cx - ns.width * 0.5, r.origin.y + 3.5),
                       7.5, NSFontWeightSemibold,
                       [NSColor colorWithWhite:1.0 alpha:(0.32 + glow * 0.68)], YES);
        }
    }
}

@end

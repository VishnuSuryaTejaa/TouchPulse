#import "TPEngine.h"
#import <math.h>

@implementation TPEngine (VisualModes)

- (void)initVisualModes {
    // Initialize Warp stars
    for (int i = 0; i < TP_MAX_STARS; i++) {
        _stars[i].x = TPRandRange(-1.0f, 1.0f);
        _stars[i].y = TPRandRange(-1.0f, 1.0f);
        _stars[i].z = TPRandRange(0.08f, 1.0f);
        _stars[i].hue = TPRandf();
        _stars[i].speed = TPRandRange(0.45f, 1.15f);
        _stars[i].px = 0.5f;
        _stars[i].py = 0.5f;
    }
    _supernovaAge = 10.0f;

    // Initialize Cyber Pet
    _petX = 0.45f;
    _petY = 0.0f;
    _petFacing = 1;
    for (int i = 0; i < TP_PET_TRAIL_N; i++) {
        _petTrailX[i] = _petX;
        _petTrailY[i] = 15.0f;
    }
}

#pragma mark - Mode 0: Plasma Fluid & Multi-Finger Lightning

- (void)stepPlasma:(float)dt {
    float t = (float)_time;

    // Subtle ambient energy + mouse comet impulse
    int mouseCell = (int)TPClampf(_mouseNormX * (TP_WAVE_N - 1), 1, TP_WAVE_N - 2);
    if (_mouseReactive) {
        _plasmaHeat[mouseCell] = MAX(_plasmaHeat[mouseCell], 0.48f);
    }

    // Active finger touches continuously inject blazing plasma & wave pulses
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        int idx = (int)TPClampf(_touches[k].x * (TP_WAVE_N - 1), 1, TP_WAVE_N - 2);
        for (int d = -3; d <= 3; d++) {
            int j = idx + d;
            if (j > 0 && j < TP_WAVE_N - 1) {
                float falloff = 1.0f - fabsf((float)d) / 4.0f;
                _waveV[j] += sinf(t * 22.0f + k * 2.1f) * 14.0f * falloff * dt;
                _plasmaHeat[j] = TPClampf(_plasmaHeat[j] + 3.2f * falloff * dt, 0.0f, 1.5f);
            }
        }
        // Ambient fingertip embers
        if (TPRandf() < 0.45f) {
            [self spawnParticleX:_touches[k].x
                               y:TPClampf(_touches[k].y * 30.0f, 3.0f, 27.0f)
                              vx:TPRandRange(-0.18f, 0.18f) + _touches[k].vx * 0.12f
                              vy:TPRandRange(-24.0f, 24.0f)
                            life:TPRandRange(0.28f, 0.65f)
                            size:TPRandRange(3.0f, 6.5f)
                             hue:fmodf(_touches[k].x + t * 0.25f, 1.0f)
                            kind:0];
        }
    }

    // 1D coupled wave equation (2 substeps for rock-solid stability)
    float subDt = MIN(dt, 0.025f) * 0.5f;
    for (int step = 0; step < 2; step++) {
        for (int i = 1; i < TP_WAVE_N - 1; i++) {
            float lap = _waveU[i - 1] + _waveU[i + 1] - 2.0f * _waveU[i];
            _waveV[i] += lap * 420.0f * subDt;
            _waveV[i] *= (1.0f - 2.4f * subDt);
        }
        for (int i = 1; i < TP_WAVE_N - 1; i++) {
            _waveU[i] += _waveV[i] * subDt;
            _waveU[i] = TPClampf(_waveU[i], -1.6f, 1.6f);
        }
    }

    // Heat diffusion & decay
    float nextHeat[TP_WAVE_N];
    nextHeat[0] = _plasmaHeat[0] * 0.9f;
    nextHeat[TP_WAVE_N - 1] = _plasmaHeat[TP_WAVE_N - 1] * 0.9f;
    for (int i = 1; i < TP_WAVE_N - 1; i++) {
        float avg = (_plasmaHeat[i - 1] + _plasmaHeat[i] * 2.0f + _plasmaHeat[i + 1]) * 0.25f;
        nextHeat[i] = avg * (1.0f - TPClampf(dt * 1.85f, 0.0f, 0.4f));
    }
    memcpy(_plasmaHeat, nextHeat, sizeof(_plasmaHeat));

    // Step Bouncing Plasma Ball Lightning Orbs!
    for (int b = 0; b < TP_MAX_BALL_LIGHTNING; b++) {
        TPBallLightning *bl = &_ballLightning[b];
        if (!bl->active) continue;
        bl->life -= dt;
        if (bl->life <= 0.0f) { bl->active = NO; continue; }
        bl->x += bl->vx * dt;
        bl->y += bl->vy * dt;
        if (bl->x < 0.015f || bl->x > 0.985f) {
            bl->x = TPClampf(bl->x, 0.015f, 0.985f);
            bl->vx = -bl->vx;
            [[TPAudioEngine shared] playSFX:TPSFXTeslaZap pan:bl->x * 2.0f - 1.0f pitchScale:TPRandRange(0.9f, 1.4f)];
            for (int p = 0; p < 10; p++) {
                [self spawnParticleX:bl->x y:bl->y vx:(bl->vx > 0 ? 1.0f : -1.0f) * TPRandRange(0.08f, 0.35f)
                                  vy:TPRandRange(-35.0f, 35.0f) life:0.35f size:3.8f hue:bl->hue kind:1];
            }
        }
        if (bl->y < 4.0f || bl->y > 26.0f) {
            bl->y = TPClampf(bl->y, 4.0f, 26.0f);
            bl->vy = -bl->vy;
        }
        int cell = (int)TPClampf(bl->x * (TP_WAVE_N - 1), 1, TP_WAVE_N - 2);
        _waveV[cell] += sinf(t * 28.0f + b) * 26.0f * dt;
        _plasmaHeat[cell] = 1.5f;
        if (TPRandf() < 0.55f) {
            [self spawnParticleX:bl->x y:bl->y vx:-bl->vx * 0.25f + TPRandRange(-0.04f, 0.04f)
                              vy:TPRandRange(-20.0f, 20.0f) life:0.28f size:3.2f hue:bl->hue kind:0];
        }
    }

    // Occasional ambient neon embers drifting across the OLED strip
    if (TPRandf() < 0.25f) {
        float rx = TPRandf();
        [self spawnParticleX:rx
                           y:TPRandRange(4.0f, 26.0f)
                          vx:TPRandRange(-0.04f, 0.04f)
                          vy:TPRandRange(-8.0f, 10.0f)
                        life:TPRandRange(0.7f, 1.4f)
                        size:TPRandRange(2.0f, 4.2f)
                         hue:fmodf(rx + t * 0.15f, 1.0f)
                        kind:0];
    }
}

- (void)touchPlasmaBegan:(float)nx y:(float)ny {
    int idx = (int)TPClampf(nx * (TP_WAVE_N - 1), 2, TP_WAVE_N - 3);
    for (int d = -5; d <= 5; d++) {
        int j = idx + d;
        if (j > 0 && j < TP_WAVE_N - 1) {
            float f = cosf(((float)d / 5.5f) * (float)M_PI_2);
            _waveV[j] += 13.5f * f;
            _plasmaHeat[j] = 1.4f;
        }
    }
    for (int i = 0; i < 16; i++) {
        float ang = TPRandRange(0, 2.0f * (float)M_PI);
        float spd = TPRandRange(0.08f, 0.32f);
        [self spawnParticleX:nx
                           y:ny * 30.0f
                          vx:cosf(ang) * spd
                          vy:sinf(ang) * 44.0f
                        life:TPRandRange(0.30f, 0.72f)
                        size:TPRandRange(3.2f, 7.0f)
                         hue:fmodf(nx + TPRandRange(-0.12f, 0.12f) + (float)_time * 0.2f, 1.0f)
                        kind:(i % 3 == 0) ? 1 : 0];
    }
    float freq = 190.0f + nx * 420.0f;
    [[TPAudioEngine shared] pluckSynthFreq:freq pan:nx * 2.0f - 1.0f velocity:0.35f waveform:0];
    [[TPAudioEngine shared] playSFX:TPSFXTeslaZap pan:nx * 2.0f - 1.0f pitchScale:TPRandRange(0.85f, 1.35f)];
}

- (void)touchPlasmaMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy {
    int idx = (int)TPClampf(nx * (TP_WAVE_N - 1), 1, TP_WAVE_N - 2);
    float mag = TPClampf(fabsf(vx) * 2.4f, 0.4f, 4.5f);
    _waveV[idx] += (vy >= 0 ? 1.0f : -1.0f) * mag * 2.8f;
    _plasmaHeat[idx] = 1.45f;
    for (int i = 0; i < 3; i++) {
        [self spawnParticleX:nx
                           y:ny * 30.0f
                          vx:vx * 0.22f + TPRandRange(-0.08f, 0.08f)
                          vy:TPRandRange(-28.0f, 28.0f)
                        life:TPRandRange(0.22f, 0.55f)
                        size:TPRandRange(2.8f, 5.8f)
                         hue:fmodf(nx + (float)_time * 0.3f, 1.0f)
                        kind:1];
    }
}

- (void)touchPlasmaEnded:(float)nx y:(float)ny vx:(float)vx vy:(float)vy {
    // Flick fast -> launch a bouncing high-voltage Ball Lightning Orb!
    if (fabsf(vx) > 0.32f) {
        for (int b = 0; b < TP_MAX_BALL_LIGHTNING; b++) {
            if (!_ballLightning[b].active) {
                TPBallLightning *bl = &_ballLightning[b];
                bl->active = YES;
                bl->x = nx;
                bl->y = TPClampf(ny * 30.0f, 5.0f, 25.0f);
                bl->vx = TPClampf(vx * 0.65f, -1.6f, 1.6f);
                if (fabsf(bl->vx) < 0.45f) bl->vx = (vx >= 0 ? 0.65f : -0.65f);
                bl->vy = TPRandRange(-22.0f, 22.0f);
                bl->life = 4.2f;
                bl->hue = fmodf(nx + (float)_time * 0.3f, 1.0f);
                bl->radius = 8.5f;
                [[TPAudioEngine shared] playSFX:TPSFXTeslaZap pan:nx * 2.0f - 1.0f pitchScale:1.45f];
                break;
            }
        }
    }
}

- (void)renderPlasma:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat midY = r.origin.y + h * 0.5;
    CGFloat cellW = w / (CGFloat)(TP_WAVE_N - 1);

    // 1. Soft OLED plasma background glow columns driven by wave + heat
    for (int i = 0; i < TP_WAVE_N; i += 4) {
        float nx = (float)i / (float)(TP_WAVE_N - 1);
        float aurora = 0.5f + 0.5f * sinf(nx * 7.5f - t * 1.9f + sinf(nx * 3.1f + t * 1.1f));
        float energy = TPClampf(aurora * 0.34f + _plasmaHeat[i] * 0.62f + fabsf(_waveU[i]) * 0.45f, 0.0f, 1.0f);
        TPRGBA col = TPThemeColor(_theme, nx * 0.85f + t * 0.14f + _waveU[i] * 0.15f, energy * 0.52f);
        CGFloat x = r.origin.x + nx * w;
        CGFloat bandH = h * (0.35f + 0.65f * energy);
        CGContextSetRGBFillColor(ctx, col.r, col.g, col.b, col.a);
        CGContextFillRect(ctx, CGRectMake(x, midY - bandH * 0.5, cellW * 4.4, bandH));
    }

    // 2. Three layered silky neon aurora + physics wave ribbons (stride 3 = 47 pts, crisp & 3x faster!)
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    for (int layer = 0; layer < 3; layer++) {
        float phase = t * (1.8f + layer * 0.65f) + layer * 2.1f;
        float freq  = 5.0f + layer * 2.8f;
        float amp   = (layer == 1) ? 7.5f : 5.2f;

        for (int pass = 0; pass < 2; pass++) {
            CGContextBeginPath(ctx);
            for (int i = 0; i < TP_WAVE_N; i += 3) {
                float nx = (float)i / (float)(TP_WAVE_N - 1);
                float baseWave = sinf(nx * freq - phase) * cosf(nx * 2.4f + t * 0.7f) * amp;
                float physWave = _waveU[i] * (layer == 1 ? 12.5f : 7.0f);
                CGFloat px = r.origin.x + nx * w;
                CGFloat py = TPClampf(midY + baseWave + physWave, r.origin.y + 1.5, r.origin.y + h - 1.5);
                if (i == 0) CGContextMoveToPoint(ctx, px, py);
                else CGContextAddLineToPoint(ctx, px, py);
            }
            TPRGBA c = TPThemeColor(_theme, t * 0.18f + layer * 0.31f, pass == 0 ? 0.35f : 0.92f);
            if (pass == 1) {
                CGContextSetRGBStrokeColor(ctx, TPLerpf(c.r, 1.0f, 0.45f), TPLerpf(c.g, 1.0f, 0.45f), TPLerpf(c.b, 1.0f, 0.45f), 0.95f);
                CGContextSetLineWidth(ctx, layer == 1 ? 1.8 : 1.1);
            } else {
                CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, 0.32f);
                CGContextSetLineWidth(ctx, layer == 1 ? 4.8 : 3.0);
            }
            CGContextStrokePath(ctx);
        }
    }

    // 3. Subtle mouse-tracking comet orb
    if (_mouseReactive) {
        CGFloat mx = r.origin.x + _mouseNormX * w;
        TPRGBA mc = TPThemeColor(_theme, _mouseNormX + t * 0.25f, 0.72f);
        TPDrawGlowCircle(ctx, mx, midY + sinf(t * 4.0f) * 3.5f, 9.5f, mc);
    }

    // 3b. Bouncing High-Voltage Plasma Ball Lightning Orbs + mini Tesla tendrils!
    for (int b = 0; b < TP_MAX_BALL_LIGHTNING; b++) {
        TPBallLightning *bl = &_ballLightning[b];
        if (!bl->active) continue;
        CGFloat bx = r.origin.x + bl->x * w;
        CGFloat by = r.origin.y + bl->y;
        float fade = TPClampf(bl->life / 0.6f, 0.0f, 1.0f);
        TPRGBA bc = TPThemeColor(_theme, bl->hue + t * 0.5f, fade);
        TPDrawGlowCircle(ctx, bx, by, bl->radius * (0.9f + 0.25f * sinf(t * 25.0f + b)), bc);
        // Crackling tendrils shooting off the ball
        for (int arc = 0; arc < 2; arc++) {
            CGFloat ax = bx + TPRandRange(-22.0, 22.0);
            CGFloat ay = TPClampf(by + TPRandRange(-12.0, 12.0), r.origin.y + 1.0, r.origin.y + h - 1.0);
            CGContextSetRGBStrokeColor(ctx, 0.9, 0.98, 1.0, fade * 0.85);
            CGContextSetLineWidth(ctx, 1.1);
            CGContextMoveToPoint(ctx, bx, by);
            CGContextAddLineToPoint(ctx, (bx + ax) * 0.5 + TPRandRange(-5, 5), (by + ay) * 0.5 + TPRandRange(-4, 4));
            CGContextAddLineToPoint(ctx, ax, ay);
            CGContextStrokePath(ctx);
        }
    }

    // 4. Multi-finger plasma orbs + FORKED TESLA COIL LIGHTNING ARCS!
    CGPoint fingerPts[TP_MAX_TOUCHES];
    int fingerCount = 0;
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        CGFloat fx = r.origin.x + _touches[k].x * w;
        CGFloat fy = r.origin.y + _touches[k].y * h;
        fingerPts[fingerCount++] = CGPointMake(fx, fy);
        TPRGBA fc = TPThemeColor(_theme, _touches[k].x + t * 0.4f, 1.0f);
        TPDrawGlowCircle(ctx, fx, fy, 15.0f + sinf(t * 18.0f) * 2.5f, fc);

        // Single-finger Tesla coil tendrils snapping wildly outward!
        for (int td = 0; td < 3; td++) {
            CGFloat ex = fx + TPRandRange(-48.0, 48.0);
            CGFloat ey = TPClampf(fy + TPRandRange(-14.0, 14.0), r.origin.y + 1.0, r.origin.y + h - 1.0);
            CGContextSetRGBStrokeColor(ctx, fc.r, fc.g, fc.b, 0.65);
            CGContextSetLineWidth(ctx, 2.2);
            CGContextMoveToPoint(ctx, fx, fy);
            CGContextAddLineToPoint(ctx, TPLerpf(fx, ex, 0.5) + TPRandRange(-6, 6), TPLerpf(fy, ey, 0.5) + TPRandRange(-5, 5));
            CGContextAddLineToPoint(ctx, ex, ey);
            CGContextStrokePath(ctx);
        }
    }

    if (fingerCount >= 2) {
        for (int a = 0; a < fingerCount - 1; a++) {
            CGPoint p0 = fingerPts[a];
            CGPoint p1 = fingerPts[a + 1];
            // Double-stranded high-voltage plasma beam between fingers!
            for (int bolt = 0; bolt < 2; bolt++) {
                int segs = 16;
                for (int pass = 0; pass < 2; pass++) {
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx, p0.x, p0.y);
                    for (int s = 1; s < segs; s++) {
                        float f = (float)s / (float)segs;
                        float jitter = (1.0f - fabsf(f * 2.0f - 1.0f)) * (bolt == 0 ? 12.0f : 16.0f);
                        CGFloat lx = TPLerpf(p0.x, p1.x, f);
                        CGFloat ly = TPClampf(TPLerpf(p0.y, p1.y, f) + TPRandRange(-jitter, jitter),
                                              r.origin.y + 1.0, r.origin.y + h - 1.0);
                        CGContextAddLineToPoint(ctx, lx, ly);
                    }
                    CGContextAddLineToPoint(ctx, p1.x, p1.y);
                    TPRGBA lc = TPThemeColor(_theme, t * 0.9f + a * 0.3f + bolt * 0.4f, pass == 0 ? 0.50f : 1.0f);
                    if (pass == 0) {
                        CGContextSetRGBStrokeColor(ctx, lc.r, lc.g, lc.b, 0.55f);
                        CGContextSetLineWidth(ctx, bolt == 0 ? 5.2 : 3.2);
                    } else {
                        CGContextSetRGBStrokeColor(ctx, 0.95, 0.99, 1.0, 1.0);
                        CGContextSetLineWidth(ctx, bolt == 0 ? 1.6 : 1.0);
                    }
                    CGContextStrokePath(ctx);
                }
            }
        }
    }
}

#pragma mark - Mode 1: Warp Drive & Black Hole Singularity

- (void)stepWarp:(float)dt {
    float t = (float)_time;

    // Check up to 2 simultaneous fingers for BINARY BLACK HOLE COLLIDER!
    int activeHoles = 0;
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        if (activeHoles == 0) {
            _bhX = _touches[k].x;
            _bhY = _touches[k].y;
            activeHoles = 1;
        } else if (activeHoles == 1) {
            _bh2X = _touches[k].x;
            _bh2Y = _touches[k].y;
            activeHoles = 2;
            break;
        }
    }
    _bhActive = (activeHoles >= 1);
    _bh2Active = (activeHoles >= 2);
    BOOL holding = _bhActive;

    if (_bhActive) {
        _bhMass = TPClampf(_bhMass + dt * 1.6f, 0.25f, 2.4f);
        if (_bh2Active) {
            _bh2Mass = TPClampf(_bh2Mass + dt * 1.8f, 0.25f, 2.4f);
            // If two black holes come close -> INSTANT BIG BANG COLLISION!
            if (fabsf(_bhX - _bh2X) < 0.08f && _supernovaAge > 0.65f) {
                _supernovaBigBang = YES;
                _supernovaAge = 0.0f;
                _supernovaX = (_bhX + _bh2X) * 0.5f;
                _supernovaY = (_bhY + _bh2Y) * 0.5f;
                [[TPAudioEngine shared] playSFX:TPSFXSupernova pan:_supernovaX * 2.0f - 1.0f pitchScale:0.75f];
                [self showToast:@"BIG BANG COLLISION!" subtitle:@"Binary Singularity Merger!"];
                for (int p = 0; p < 55; p++) {
                    float ang = TPRandRange(0, 6.283f);
                    [self spawnParticleX:_supernovaX y:_supernovaY * 30.0f vx:cosf(ang) * TPRandRange(0.2f, 0.85f)
                                      vy:sinf(ang) * 65.0f life:TPRandRange(0.45f, 1.15f) size:TPRandRange(3.0f, 6.8f)
                                     hue:TPRandf() kind:1];
                }
            }
        } else {
            _bh2Mass = MAX(0.0f, _bh2Mass - dt * 3.5f);
        }
        [[TPAudioEngine shared] setDroneLevel:TPClampf((_bhMass + _bh2Mass) * 0.35f, 0.15f, 0.95f)
                                         freq:52.0f + (_bhMass + _bh2Mass) * 34.0f
                                          pan:_bhX * 2.0f - 1.0f];
    } else {
        _bhMass = MAX(0.0f, _bhMass - dt * 3.5f);
        _bh2Mass = MAX(0.0f, _bh2Mass - dt * 3.5f);
        [[TPAudioEngine shared] setDroneLevel:0.0f freq:55.0f pan:0.0f];
    }

    if (_supernovaAge < 2.0f) {
        _supernovaAge += dt;
    }

    float vanishX = _mouseReactive ? TPLerpf(0.25f, 0.75f, _mouseNormX) : (0.5f + sinf(t * 0.35f) * 0.18f);
    float warpBoost = holding ? 1.85f : (1.0f + (_supernovaAge < 0.6f ? (0.6f - _supernovaAge) * 3.2f : 0.0f));

    for (int i = 0; i < TP_MAX_STARS; i++) {
        TPStar *s = &_stars[i];
        float oldZ = MAX(0.03f, s->z);
        s->px = vanishX + (s->x / oldZ) * 0.42f;
        s->py = 0.5f + (s->y / oldZ) * 0.45f;

        s->z -= dt * s->speed * 0.58f * warpBoost;

        // Gravitational lensing pull toward active Black Hole
        if (_bhActive) {
            float sx = vanishX + (s->x / MAX(0.05f, s->z)) * 0.42f;
            float sy = 0.5f + (s->y / MAX(0.05f, s->z)) * 0.45f;
            float dx = _bhX - sx;
            float dy = (_bhY - sy) * 0.25f;
            float distSq = dx * dx + dy * dy + 0.004f;
            float pull = (_bhMass * 0.018f) / distSq;
            pull = MIN(pull, 3.0f);
            // Swirl + inward spiral
            s->x += (dx * pull - dy * pull * 1.4f) * dt * s->z;
            s->y += (dy * pull + dx * pull * 0.8f) * dt * s->z;
        }

        // Supernova radial blast
        if (_supernovaAge < 0.45f) {
            float sx = vanishX + (s->x / MAX(0.05f, s->z)) * 0.42f;
            float dx = sx - _supernovaX;
            s->x += (dx >= 0 ? 1.0f : -1.0f) * dt * 2.2f * (0.45f - _supernovaAge);
        }

        float curX = vanishX + (s->x / MAX(0.03f, s->z)) * 0.42f;
        if (s->z <= 0.04f || curX < -0.15f || curX > 1.15f) {
            s->x = TPRandRange(-1.1f, 1.1f);
            s->y = TPRandRange(-0.95f, 0.95f);
            s->z = TPRandRange(0.75f, 1.05f);
            s->px = vanishX + (s->x / s->z) * 0.42f;
            s->py = 0.5f + (s->y / s->z) * 0.45f;
            s->hue = TPRandf();
        }
    }
}

- (void)touchWarpEnded:(float)nx y:(float)ny {
    if (_bhMass > 0.22f) {
        // Trigger SUPERNOVA SHOCKWAVE!
        _supernovaAge = 0.0f;
        _supernovaX = nx;
        _supernovaY = ny;
        [[TPAudioEngine shared] playSFX:TPSFXSupernova pan:nx * 2.0f - 1.0f pitchScale:1.0f];
        for (int i = 0; i < 36; i++) {
            float ang = TPRandRange(0, 2.0f * (float)M_PI);
            float spd = TPRandRange(0.15f, 0.65f);
            [self spawnParticleX:nx
                               y:ny * 30.0f
                              vx:cosf(ang) * spd
                              vy:sinf(ang) * 55.0f
                            life:TPRandRange(0.35f, 0.95f)
                            size:TPRandRange(2.5f, 6.2f)
                             hue:TPRandf()
                            kind:1];
        }
    }
}

- (void)renderWarp:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    float vanishX = _mouseReactive ? TPLerpf(0.25f, 0.75f, _mouseNormX) : (0.5f + sinf(t * 0.35f) * 0.18f);

    // Subtle deep-space nebula band
    for (int i = 0; i < 40; i++) {
        float nx = (float)i / 40.0f;
        float neb = 0.5f + 0.5f * sinf(nx * 5.2f + t * 0.4f);
        TPRGBA nc = TPThemeColor(_theme, nx + t * 0.06f, 0.14f * neb);
        CGContextSetRGBFillColor(ctx, nc.r, nc.g, nc.b, nc.a);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + nx * w, r.origin.y, w / 39.0, h));
    }

    // Starfield hyperspace streaks
    for (int i = 0; i < TP_MAX_STARS; i++) {
        TPStar *s = &_stars[i];
        float depth = 1.0f - TPClampf(s->z, 0.0f, 1.0f);
        CGFloat x1 = r.origin.x + (vanishX + (s->x / MAX(0.03f, s->z)) * 0.42f) * w;
        CGFloat y1 = r.origin.y + (0.5f + (s->y / MAX(0.03f, s->z)) * 0.45f) * h;
        CGFloat x0 = r.origin.x + s->px * w;
        CGFloat y0 = r.origin.y + s->py * h;

        TPRGBA sc = TPThemeColor(_theme, s->hue + t * 0.12f, 0.25f + 0.75f * depth);
        // Chromatic cyan/magenta streak + white core
        CGContextSetRGBStrokeColor(ctx, sc.r, sc.g, sc.b, sc.a * 0.75f);
        CGContextSetLineWidth(ctx, 0.8 + depth * 2.1);
        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddLineToPoint(ctx, x1, y1);
        CGContextStrokePath(ctx);

        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.35 + 0.65 * depth);
        CGFloat rad = 0.6 + depth * 1.4;
        CGContextFillEllipseInRect(ctx, CGRectMake(x1 - rad, y1 - rad, rad * 2.0, rad * 2.0));
    }

    // Active Black Hole Event Horizons + Binary Tidal Plasma Jet!
    float holeX[2] = { _bhX, _bh2X };
    float holeY[2] = { _bhY, _bh2Y };
    float holeM[2] = { _bhMass, _bh2Mass };

    if (_bhMass > 0.15f && _bh2Mass > 0.15f) {
        // Tidal plasma bridge ripping between the two binary black holes!
        CGFloat x0 = r.origin.x + _bhX * w, y0 = r.origin.y + _bhY * h;
        CGFloat x1 = r.origin.x + _bh2X * w, y1 = r.origin.y + _bh2Y * h;
        TPRGBA jc = TPThemeColor(_theme, fmodf(t * 1.4f, 1.0f), 0.85f);
        CGContextSetRGBStrokeColor(ctx, jc.r, jc.g, jc.b, 0.55f);
        CGContextSetLineWidth(ctx, 6.0);
        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddQuadCurveToPoint(ctx, (x0 + x1) * 0.5, (y0 + y1) * 0.5 + sinf(t * 18.0f) * 9.0, x1, y1);
        CGContextStrokePath(ctx);
        CGContextSetRGBStrokeColor(ctx, 1.0, 0.95, 0.85, 0.95);
        CGContextSetLineWidth(ctx, 1.6);
        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddQuadCurveToPoint(ctx, (x0 + x1) * 0.5, (y0 + y1) * 0.5 - sinf(t * 18.0f) * 7.0, x1, y1);
        CGContextStrokePath(ctx);
    }

    for (int hi = 0; hi < 2; hi++) {
        if (holeM[hi] <= 0.05f) continue;
        CGFloat cx = r.origin.x + holeX[hi] * w;
        CGFloat cy = r.origin.y + holeY[hi] * h;
        CGFloat rad = 6.0 + holeM[hi] * 11.0;

        for (int ring = 0; ring < 3; ring++) {
            float rf = 1.0f + ring * 0.45f;
            TPRGBA rc = TPThemeColor(_theme, fmodf(t * 0.8f + ring * 0.22f + hi * 0.45f, 1.0f),
                                     (0.85f - ring * 0.24f) * MIN(1.0f, holeM[hi]));
            CGContextSetRGBStrokeColor(ctx, rc.r, rc.g, rc.b, rc.a);
            CGContextSetLineWidth(ctx, 2.2 - ring * 0.5);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - rad * rf * 1.7, cy - rad * rf * 0.65,
                                                         rad * rf * 3.4, rad * rf * 1.3));
        }

        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
        CGContextFillEllipseInRect(ctx, CGRectMake(cx - rad * 0.72, cy - rad * 0.72, rad * 1.44, rad * 1.44));

        CGContextSetRGBStrokeColor(ctx, 1.0, 0.92, 0.72, 0.95);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - rad * 0.75, cy - rad * 0.75, rad * 1.50, rad * 1.50));
    }

    // Expanding RGB Chromatic Supernova / Big Bang Shockwave Rings!
    if (_supernovaAge < 0.95f) {
        float p = _supernovaAge / 0.95f;
        CGFloat cx = r.origin.x + _supernovaX * w;
        CGFloat cy = r.origin.y + _supernovaY * h;
        if (_supernovaBigBang && p < 0.25f) {
            CGContextSetRGBFillColor(ctx, 1.0, 0.95, 0.9, (0.25f - p) * 2.6f);
            CGContextFillRect(ctx, r);
        }
        static const float rgb[3][3] = { {1.0f, 0.2f, 0.45f}, {0.1f, 0.98f, 1.0f}, {1.0f, 0.88f, 0.25f} };
        for (int c = 0; c < 3; c++) {
            float cp = TPClampf(p - c * 0.05f, 0.0f, 1.0f);
            CGFloat rx = cp * w * 0.75;
            CGFloat ry = 8.0 + cp * 82.0;
            CGContextSetRGBStrokeColor(ctx, rgb[c][0], rgb[c][1], rgb[c][2], (1.0f - cp) * 0.95f);
            CGContextSetLineWidth(ctx, 4.2 * (1.0f - cp) + 0.8);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - rx, cy - ry, rx * 2.0, ry * 2.0));
        }
    }
}

#pragma mark - Mode 5: Cyber Pet & Nyan Squad

- (void)triggerPetTurbo {
    _petTurboTimer = 5.0f;
    _petIdleTime = 0.0f;
    _petVY = 38.0f;
    [[TPAudioEngine shared] playSFX:TPSFXCoin pan:_petX * 2.0f - 1.0f pitchScale:1.25f];
    [self showToast:@"NYAN TURBO!" subtitle:@"Rainbow Hyperdrive Activated"];
}

- (void)stepPet:(float)dt {
    _petIdleTime += dt;
    if (_petHappyTimer > 0.0f) _petHappyTimer = MAX(0.0f, _petHappyTimer - dt);

    if (_petFlipAngle > 0.0f) {
        _petFlipAngle = MAX(0.0f, _petFlipAngle - dt * 11.0f);
    }

    // Update bouncing treat
    if (_treatActive) {
        _treatVY -= 110.0f * dt;
        _treatY += _treatVY * dt;
        if (_treatY < 4.0f) {
            _treatY = 4.0f;
            _treatVY = fabsf(_treatVY) * 0.55f;
            if (_treatVY < 8.0f) _treatVY = 0.0f;
        }
    }

    if (_petTurboTimer > 0.0f) {
        _petTurboTimer = MAX(0.0f, _petTurboTimer - dt);
        _petFacing = 1;
        _petX += 0.42f * dt;
        if (_petX > 1.06f) _petX = -0.06f;
        _petY = 6.0f + sinf((float)_time * 16.0f) * 4.5f;
        _petWalkPhase += dt * 24.0f;
        // Trailing rainbow stars
        if (TPRandf() < 0.55f) {
            [self spawnParticleX:_petX - 0.03f
                               y:8.0f + _petY + TPRandRange(-6.0f, 6.0f)
                              vx:-0.12f
                              vy:TPRandRange(-10.0f, 10.0f)
                            life:0.55f
                            size:3.2f
                             hue:TPRandf()
                            kind:3];
        }
    } else {
        // Decide target: treat > active touch > mouse cursor > gentle wander
        float targetX = _petX;
        float moveSpeed = 0.16f;
        BOOL hasGoal = NO;

        if (_treatActive) {
            targetX = _treatX;
            moveSpeed = 0.34f;
            hasGoal = YES;
            if (fabsf(_treatX - _petX) < 0.025f) {
                // Caught the treat!
                _treatActive = NO;
                _petVY = 55.0f;
                _petHappyTimer = 2.0f;
                _petIdleTime = 0.0f;
                [[TPAudioEngine shared] playSFX:TPSFXPetChirp pan:_petX * 2.0f - 1.0f pitchScale:1.15f];
                for (int i = 0; i < 6; i++) {
                    [self spawnParticleX:_petX
                                       y:16.0f
                                      vx:TPRandRange(-0.06f, 0.06f)
                                      vy:TPRandRange(12.0f, 28.0f)
                                    life:TPRandRange(0.7f, 1.3f)
                                    size:4.0f
                                     hue:TPRandf()
                                    kind:(i % 2 == 0) ? 2 : 0];
                }
            }
        } else if (_mouseReactive) {
            float diff = fabsf(_mouseNormX - _petX);
            if (diff > 0.055f) {
                targetX = _mouseNormX;
                moveSpeed = 0.18f;
                hasGoal = YES;
                _petIdleTime = 0.0f;
            }
        }

        if (hasGoal) {
            float dx = targetX - _petX;
            _petFacing = (dx >= 0.0f) ? 1 : -1;
            float step = TPClampf(dx * 3.5f, -moveSpeed, moveSpeed);
            _petX = TPClampf(_petX + step * dt, 0.04f, 0.94f);
            _petWalkPhase += dt * (8.0f + fabsf(step) * 45.0f);
        }

        // Gravity on pet hops
        if (_petY > 0.0f || _petVY != 0.0f) {
            _petVY -= 180.0f * dt;
            _petY += _petVY * dt;
            if (_petY <= 0.0f) {
                _petY = 0.0f;
                _petVY = 0.0f;
            }
        }
    }

    // Record rainbow trail ring
    _petTrailX[_petTrailHead] = _petX;
    _petTrailY[_petTrailHead] = 11.0f + _petY;
    _petTrailHead = (_petTrailHead + 1) % TP_PET_TRAIL_N;
}

- (void)touchPetBegan:(float)nx y:(float)ny {
    _petIdleTime = 0.0f;
    // Right-edge Turbo Rocket button
    if (nx > 0.91f) {
        [self triggerPetTurbo];
        return;
    }

    if (fabsf(nx - _petX) < 0.055f) {
        // Petting the cyber cat directly -> purr + happy flip + hearts!
        _petHappyTimer = 2.5f;
        _petVY = 58.0f;
        _petFlipAngle = (float)(2.0 * M_PI);
        [[TPAudioEngine shared] playSFX:TPSFXPetChirp pan:_petX * 2.0f - 1.0f pitchScale:TPRandRange(0.95f, 1.3f)];
        for (int i = 0; i < 5; i++) {
            [self spawnParticleX:_petX + TPRandRange(-0.02f, 0.02f)
                               y:16.0f
                              vx:TPRandRange(-0.05f, 0.05f)
                              vy:TPRandRange(12.0f, 24.0f)
                            life:TPRandRange(0.75f, 1.35f)
                            size:5.0f
                             hue:TPRandf()
                            kind:2];
        }
    } else {
        // Drop a glowing neon treat for the pet to chase!
        _treatActive = YES;
        _treatX = TPClampf(nx, 0.05f, 0.89f);
        _treatY = 22.0f;
        _treatVY = 12.0f;
        [[TPAudioEngine shared] playSFX:TPSFXClick pan:nx * 2.0f - 1.0f pitchScale:1.4f];
    }
}

- (void)touchPetMoved:(float)nx y:(float)ny {
    if (fabsf(nx - _petX) < 0.055f && TPRandf() < 0.22f) {
        _petHappyTimer = 2.0f;
        [self spawnParticleX:_petX + TPRandRange(-0.02f, 0.02f)
                           y:18.0f
                          vx:TPRandRange(-0.03f, 0.03f)
                          vy:TPRandRange(10.0f, 20.0f)
                        life:0.9f
                        size:4.5f
                         hue:TPRandf()
                        kind:2];
    }
}

- (void)renderPet:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;

    // 1. Twinkling pixel night sky
    for (int i = 0; i < 22; i++) {
        float sx = fmodf((float)i * 0.137f + (_petTurboTimer > 0 ? -t * 0.28f : -t * 0.015f), 1.0f);
        if (sx < 0) sx += 1.0f;
        float sy = 5.0f + fmodf((float)i * 9.7f, 21.0f);
        float tw = 0.35f + 0.65f * sinf(t * 3.5f + i * 1.9f);
        CGContextSetRGBFillColor(ctx, 0.85, 0.92, 1.0, tw * 0.75);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + sx * w, r.origin.y + sy, 1.8, 1.8));
    }

    // Subtle neon floor line
    TPRGBA floorC = TPThemeColor(_theme, 0.2f, 0.35f);
    CGContextSetRGBFillColor(ctx, floorC.r, floorC.g, floorC.b, floorC.a);
    CGContextFillRect(ctx, CGRectMake(r.origin.x, r.origin.y + 1.0, w, 1.2));

    // 2. Nyan 6-stripe rainbow ribbon trail (vivid during turbo, subtle shimmer normally)
    static const float rainbow[6][3] = {
        {1.00f, 0.15f, 0.22f},
        {1.00f, 0.56f, 0.08f},
        {1.00f, 0.94f, 0.15f},
        {0.20f, 0.95f, 0.35f},
        {0.10f, 0.72f, 1.00f},
        {0.62f, 0.28f, 1.00f}
    };
    float trailAlpha = (_petTurboTimer > 0.0f) ? 0.92f : ((_petHappyTimer > 0.0f) ? 0.55f : 0.28f);
    int trailSteps = (_petTurboTimer > 0.0f) ? 28 : 14;
    for (int s = 0; s < trailSteps; s++) {
        float frac = 1.0f - (float)s / (float)trailSteps;
        CGFloat segX = r.origin.x + (_petX - _petFacing * (0.014f + s * 0.0055f)) * w;
        CGFloat wave = sinf(t * 14.0f - s * 0.6f) * (_petTurboTimer > 0 ? 2.2f : 1.0f);
        CGFloat baseY = r.origin.y + 6.0 + _petY + wave;
        for (int band = 0; band < 6; band++) {
            CGContextSetRGBFillColor(ctx, rainbow[band][0], rainbow[band][1], rainbow[band][2], trailAlpha * frac);
            CGContextFillRect(ctx, CGRectMake(segX, baseY + (5 - band) * 2.1, w * 0.0062, 2.1));
        }
    }

    // 3. Glowing neon treat if active
    if (_treatActive) {
        CGFloat tx = r.origin.x + _treatX * w;
        CGFloat ty = r.origin.y + _treatY + 4.0;
        TPDrawGlowCircle(ctx, tx, ty, 7.5f, (TPRGBA){1.0f, 0.85f, 0.18f, 1.0f});
    }

    // 4. Crisp Pixel-Art Cyber Nyan Cat!
    CGFloat px = r.origin.x + _petX * w;
    CGFloat py = r.origin.y + 4.0 + _petY;
    BOOL sleeping = (_petIdleTime > 7.5f && _petTurboTimer <= 0.0f && !_treatActive);

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, px, py + 9.0);
    if (_petFlipAngle > 0.01f) {
        CGContextRotateCTM(ctx, _petFlipAngle);
    }
    if (_petFacing < 0) {
        CGContextScaleCTM(ctx, -1.0, 1.0);
    }

    // Body (Pop-tart cyber chassis!)
    TPRGBA bodyGlow = TPThemeColor(_theme, fmodf(t * 0.25f, 1.0f), 1.0f);
    TPDrawRoundedRect(ctx, CGRectMake(-11, -5, 18, 12), 2.5);
    CGContextSetRGBFillColor(ctx, 0.96, 0.78, 0.56, 1.0); // biscuit border
    CGContextFillPath(ctx);

    TPDrawRoundedRect(ctx, CGRectMake(-9.5, -3.5, 15, 9), 2.0);
    CGContextSetRGBFillColor(ctx, 1.0, 0.42, 0.76, 1.0);  // strawberry cyber frosting
    CGContextFillPath(ctx);

    // Neon sprinkles
    CGContextSetRGBFillColor(ctx, bodyGlow.r, bodyGlow.g, bodyGlow.b, 1.0);
    CGContextFillRect(ctx, CGRectMake(-7, 2, 2, 2));
    CGContextFillRect(ctx, CGRectMake(-2, -1.5, 2, 2));
    CGContextFillRect(ctx, CGRectMake(2, 2.5, 2, 2));

    // Wagging tail
    float tailWag = sinf(t * (_petTurboTimer > 0 ? 28.0f : 9.0f)) * 2.5f;
    CGContextSetRGBStrokeColor(ctx, 0.72, 0.74, 0.80, 1.0);
    CGContextSetLineWidth(ctx, 2.2);
    CGContextMoveToPoint(ctx, -11, 0);
    CGContextAddLineToPoint(ctx, -16, 2.5 + tailWag);
    CGContextStrokePath(ctx);

    // Animated little paws
    float leg = sleeping ? 0.0f : sinf(_petWalkPhase) * 2.4f;
    CGContextSetRGBFillColor(ctx, 0.75, 0.78, 0.84, 1.0);
    CGContextFillRect(ctx, CGRectMake(-9 + leg, -8.5, 3.0, 3.8));
    CGContextFillRect(ctx, CGRectMake(-2 - leg, -8.5, 3.0, 3.8));
    CGContextFillRect(ctx, CGRectMake(4 + leg, -8.5, 3.0, 3.8));

    // Cat Head
    TPDrawRoundedRect(ctx, CGRectMake(4.0, -3.0, 11.0, 10.0), 3.0);
    CGContextSetRGBFillColor(ctx, 0.78, 0.80, 0.86, 1.0);
    CGContextFillPath(ctx);

    // Ears
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 5.0, 6.5);
    CGContextAddLineToPoint(ctx, 6.5, 11.0);
    CGContextAddLineToPoint(ctx, 8.8, 6.5);
    CGContextMoveToPoint(ctx, 10.5, 6.5);
    CGContextAddLineToPoint(ctx, 13.0, 11.0);
    CGContextAddLineToPoint(ctx, 14.2, 6.5);
    CGContextFillPath(ctx);

    // Glowing Cyber Visor / Eyes!
    if (sleeping) {
        CGContextSetRGBStrokeColor(ctx, 0.15, 0.18, 0.25, 1.0);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextMoveToPoint(ctx, 7.0, 2.2);
        CGContextAddLineToPoint(ctx, 9.5, 2.2);
        CGContextMoveToPoint(ctx, 11.0, 2.2);
        CGContextAddLineToPoint(ctx, 13.5, 2.2);
        CGContextStrokePath(ctx);
    } else if (_petTurboTimer > 0.0f) {
        // Blazing cyan cyber shades during Nyan Turbo!
        CGContextSetRGBFillColor(ctx, 0.0, 0.98, 1.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(6.8, 1.2, 7.4, 2.8));
    } else {
        // Cute shiny eyes + pink blush cheeks
        CGContextSetRGBFillColor(ctx, 0.08, 0.10, 0.16, 1.0);
        CGContextFillRect(ctx, CGRectMake(7.2, 1.8, 2.0, 2.4));
        CGContextFillRect(ctx, CGRectMake(11.4, 1.8, 2.0, 2.4));
        CGContextSetRGBFillColor(ctx, 1.0, 0.45, 0.65, 0.9);
        CGContextFillRect(ctx, CGRectMake(6.0, -0.4, 2.0, 1.5));
        CGContextFillRect(ctx, CGRectMake(12.6, -0.4, 2.0, 1.5));
    }

    CGContextRestoreGState(ctx);

    // Mini Cyber Nyan Squad wingmen rocketing behind in V-formation during Turbo!
    if (_petTurboTimer > 0.0f) {
        for (int wing = 0; wing < 2; wing++) {
            float wxNorm = fmodf(_petX - (wing == 0 ? 0.09f : 0.16f) + 1.12f, 1.12f) - 0.06f;
            CGFloat wx = r.origin.x + wxNorm * w;
            CGFloat wy = r.origin.y + (wing == 0 ? 19.0 : 6.0) + sinf(t * 20.0f + wing * 2.5f) * 2.5;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, wx, wy);
            CGContextScaleCTM(ctx, 0.58, 0.58);
            TPDrawRoundedRect(ctx, CGRectMake(-10, -4, 16, 10), 2.0);
            CGContextSetRGBFillColor(ctx, wing == 0 ? 0.0 : 1.0, wing == 0 ? 0.92 : 0.85, 1.0, 0.95);
            CGContextFillPath(ctx);
            TPDrawRoundedRect(ctx, CGRectMake(4, -2, 9, 8), 2.5);
            CGContextSetRGBFillColor(ctx, 0.85, 0.88, 0.95, 1.0);
            CGContextFillPath(ctx);
            CGContextSetRGBFillColor(ctx, 1.0, 0.18, 0.65, 1.0);
            CGContextFillRect(ctx, CGRectMake(6.5, 1.0, 5.5, 2.2));
            CGContextRestoreGState(ctx);
        }
    }

    // Sleeping "Zzz" floating above pet
    if (sleeping) {
        float bob = sinf(t * 2.2f) * 2.0f;
        TPDrawText(ctx, @"zZ", CGPointMake(px + 12.0, py + 14.0 + bob), 8.5, NSFontWeightBold,
                   [NSColor colorWithRed:0.65 green:0.85 blue:1.0 alpha:0.85], NO);
    }

    // Right-edge Turbo Boost pill
    CGFloat pillW = 54.0;
    CGRect turboRect = CGRectMake(r.origin.x + w - pillW - 3.0, r.origin.y + 4.0, pillW, h - 8.0);
    TPDrawRoundedRect(ctx, turboRect, 6.0);
    if (_petTurboTimer > 0.0f) {
        TPRGBA tc = TPThemeColor(_theme, fmodf(t * 2.0f, 1.0f), 0.9f);
        CGContextSetRGBFillColor(ctx, tc.r, tc.g, tc.b, 0.35f);
        CGContextFillPath(ctx);
        TPDrawRoundedRect(ctx, CGRectInset(turboRect, 0.5, 0.5), 5.5);
        CGContextSetRGBStrokeColor(ctx, tc.r, tc.g, tc.b, 1.0f);
        CGContextSetLineWidth(ctx, 1.3);
        CGContextStrokePath(ctx);
    } else {
        CGContextSetRGBFillColor(ctx, 0.14, 0.14, 0.20, 0.85);
        CGContextFillPath(ctx);
        TPDrawRoundedRect(ctx, CGRectInset(turboRect, 0.5, 0.5), 5.5);
        CGContextSetRGBStrokeColor(ctx, 1.0, 0.45, 0.8, 0.55);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextStrokePath(ctx);
    }
    NSString *tLbl = _petTurboTimer > 0 ? @"★ BOOST" : @"★ TURBO";
    CGSize ts = TPMeasureText(tLbl, 9.0, NSFontWeightBold, NO);
    TPDrawText(ctx, tLbl,
               CGPointMake(turboRect.origin.x + (turboRect.size.width - ts.width) * 0.5,
                           turboRect.origin.y + (turboRect.size.height - ts.height) * 0.5),
               9.0, NSFontWeightBold, [NSColor whiteColor], NO);
}

#pragma mark - Mode 6: Spectrum Pulse (Live Mic FFT + Interactive Touch Beat)

- (void)stepSpectrum:(float)dt {
    _specPhase += dt;
    float t = _specPhase;

    BOOL micOn = [TPAudioEngine shared].micActive;
    float micVals[TP_SPECTRUM_BANDS];
    if (micOn) {
        [[TPAudioEngine shared] copyMicSpectrum:micVals count:TP_SPECTRUM_BANDS];
    }

    // Active touches boost nearby frequency bands!
    for (int k = 0; k < TP_MAX_TOUCHES; k++) {
        if (!_touches[k].active) continue;
        float bandF = _touches[k].x * (TP_SPECTRUM_BANDS - 1);
        for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
            float d = fabsf((float)b - bandF);
            if (d < 4.0f) {
                float add = (1.0f - d / 4.0f) * (0.55f + 0.45f * _touches[k].y);
                _specTouchBoost[b] = MAX(_specTouchBoost[b], add);
            }
        }
    }

    float beat = powf(MAX(0.0f, sinf(t * 6.283f * 1.95f)), 4.0f); // ~117 BPM pulse

    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        float normB = (float)b / (float)(TP_SPECTRUM_BANDS - 1);
        float target = 0.0f;

        if (micOn) {
            target = micVals[b];
        } else {
            // Lush musical reactive spectrum (sub-bass kick on left, shimmering harmonics across)
            float bassEnvelope = expf(-normB * 3.8f) * (0.28f + 0.65f * beat);
            float midWave = (0.25f + 0.32f * sinf(normB * 11.0f - t * 4.4f) * cosf(normB * 5.0f + t * 2.3f));
            float mouseGlow = _mouseReactive ? expf(-powf((normB - _mouseNormX) * 6.5f, 2.0f)) * 0.42f : 0.0f;
            float shimmer = 0.10f * sinf(t * 11.0f + b * 1.7f);
            target = TPClampf(bassEnvelope + midWave * 0.55f + mouseGlow + shimmer, 0.06f, 0.96f);
        }

        // Layer touch boost smoothly on top
        target = TPClampf(MAX(target, _specTouchBoost[b]), 0.04f, 1.0f);
        _specTouchBoost[b] = MAX(0.0f, _specTouchBoost[b] - dt * 2.1f);

        // Smooth rise, crisp decay
        float rate = (target > _specBars[b]) ? 24.0f : 11.0f;
        _specBars[b] = TPLerpf(_specBars[b], target, TPClampf(dt * rate, 0.0f, 1.0f));

        // Peak-hold physics with gravity
        if (_specBars[b] >= _specPeaks[b]) {
            _specPeaks[b] = _specBars[b];
            _specPeakVel[b] = 0.0f;
        } else {
            _specPeakVel[b] += 1.45f * dt;
            _specPeaks[b] = MAX(_specBars[b], _specPeaks[b] - _specPeakVel[b] * dt);
        }
    }
}

- (void)touchSpectrumAt:(float)nx y:(float)ny strong:(BOOL)strong {
    float bandF = nx * (TP_SPECTRUM_BANDS - 1);
    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        float d = fabsf((float)b - bandF);
        if (d < 5.0f) {
            _specTouchBoost[b] = MAX(_specTouchBoost[b], (1.0f - d / 5.0f) * (strong ? 1.0f : 0.82f));
        }
    }
    if (strong) {
        float freq = [TPAudioEngine frequencyForScale:_synthScale index:(int)(nx * 17.0f) totalKeys:18];
        [[TPAudioEngine shared] pluckSynthFreq:freq pan:nx * 2.0f - 1.0f velocity:0.42f waveform:0];
        for (int i = 0; i < 8; i++) {
            [self spawnParticleX:nx
                               y:ny * 26.0f
                              vx:TPRandRange(-0.08f, 0.08f)
                              vy:TPRandRange(10.0f, 34.0f)
                            life:0.42f
                            size:3.5f
                             hue:nx
                            kind:0];
        }
    }
}

- (void)renderSpectrum:(CGContextRef)ctx rect:(CGRect)r {
    float t = (float)_time;
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat gap = 2.2;
    CGFloat barW = (w - gap * (TP_SPECTRUM_BANDS + 1)) / (CGFloat)TP_SPECTRUM_BANDS;
    if (barW < 2.0) barW = 2.0;

    // 1. Segmented OLED LED Spectrum Bars + Peak Caps
    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        float normB = (float)b / (float)(TP_SPECTRUM_BANDS - 1);
        CGFloat x = r.origin.x + gap + b * (barW + gap);
        float val = _specBars[b];
        CGFloat totalBarH = val * (h - 5.0);

        int segs = 7;
        CGFloat segH = (h - 6.0) / (CGFloat)segs;
        int litSegs = (int)ceilf(val * (float)segs);

        for (int s = 0; s < litSegs; s++) {
            float sf = (float)s / (float)segs;
            TPRGBA col = TPThemeColor(_theme, normB * 0.72f + sf * 0.25f + t * 0.08f, 0.92f);
            CGFloat sy = r.origin.y + 2.0 + s * segH;
            CGRect segR = CGRectMake(x, sy, barW, segH - 1.3);
            TPDrawRoundedRect(ctx, segR, 1.2);
            CGContextSetRGBFillColor(ctx, col.r, col.g, col.b, col.a);
            CGContextFillPath(ctx);
        }

        // Subtle soft aura column behind bright bars
        if (totalBarH > 4.0) {
            TPRGBA ac = TPThemeColor(_theme, normB + t * 0.08f, 0.16f);
            CGContextSetRGBFillColor(ctx, ac.r, ac.g, ac.b, ac.a);
            CGContextFillRect(ctx, CGRectMake(x - 1.0, r.origin.y + 2.0, barW + 2.0, totalBarH));
        }

        // Crisp white-tinted peak-hold cap
        CGFloat py = r.origin.y + 2.0 + _specPeaks[b] * (h - 6.0);
        TPRGBA pc = TPThemeColor(_theme, normB + 0.15f, 1.0f);
        CGContextSetRGBFillColor(ctx, TPLerpf(pc.r, 1.0f, 0.65f), TPLerpf(pc.g, 1.0f, 0.65f), TPLerpf(pc.b, 1.0f, 0.65f), 0.98f);
        CGContextFillRect(ctx, CGRectMake(x, py, barW, 1.8));
    }

    // 2. Smooth translucent live waveform ribbon gliding across the bars
    CGContextBeginPath(ctx);
    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        CGFloat x = r.origin.x + gap + b * (barW + gap) + barW * 0.5;
        CGFloat y = r.origin.y + 4.0 + _specBars[b] * (h - 10.0);
        if (b == 0) CGContextMoveToPoint(ctx, x, y);
        else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.35);
    CGContextSetLineWidth(ctx, 1.2);
    CGContextStrokePath(ctx);

    // 3. Subtle LIVE MIC badge in top-right when mic FFT is active
    if ([TPAudioEngine shared].micActive) {
        float pulse = 0.55f + 0.45f * sinf(t * 5.0f);
        CGRect badge = CGRectMake(r.origin.x + w - 58.0, r.origin.y + h - 13.0, 54.0, 11.5);
        TPDrawRoundedRect(ctx, badge, 5.5);
        CGContextSetRGBFillColor(ctx, 0.06, 0.06, 0.10, 0.82);
        CGContextFillPath(ctx);
        CGContextSetRGBFillColor(ctx, 1.0, 0.22, 0.28, pulse);
        CGContextFillEllipseInRect(ctx, CGRectMake(badge.origin.x + 5.0, badge.origin.y + 3.2, 5.0, 5.0));
        TPDrawText(ctx, @"MIC LIVE", CGPointMake(badge.origin.x + 12.5, badge.origin.y + 0.2),
                   7.5, NSFontWeightBold, [NSColor whiteColor], YES);
    }
}

@end

#import "TPCommon.h"
#import <math.h>

NSString *TPModeName(TPMode mode) {
    switch (mode) {
        case TPModePlasma:   return @"Chaos Plasma";
        case TPModeWarp:     return @"Black Hole Collider";
        case TPModeFire:     return @"Inferno & Fireworks";
        case TPModeMatrix:   return @"Matrix Breach";
        case TPModeBeatbox:  return @"808 Beatbox";
        case TPModePhysics:  return @"Mercury Vortex";
        case TPModeRunner:   return @"Cyber Runner";
        case TPModeBlaster:  return @"Laser Blaster";
        case TPModeSynth:    return @"Neon Laser Synth";
        case TPModePet:      return @"Cyber Nyan Squad";
        case TPModeSpectrum: return @"Spectrum Pulse";
        case TPModeTools:    return @"Power HUD Deck";
        default:             return @"TouchPulse";
    }
}

NSString *TPModeSubtitle(TPMode mode) {
    switch (mode) {
        case TPModePlasma:   return @"Tesla forked lightning, flick for ball lightning";
        case TPModeWarp:     return @"Hold 1–2 fingers for binary Black Hole Big Bang";
        case TPModeFire:     return @"Real pixel fire, flamethrower drag & fireworks";
        case TPModeMatrix:   return @"Digital Katakana rain & touch glitch breaches";
        case TPModeBeatbox:  return @"Live 16-step TR-808 drum & 303 acid machine";
        case TPModePhysics:  return @"80 colliding orbs — hold for magnetic tornado";
        case TPModeRunner:   return @"Tap to jump & double-jump over neon lasers";
        case TPModeBlaster:  return @"Multi-touch arcade — zap meteors for combos";
        case TPModeSynth:    return @"Playable stereo polyphonic Laser Harp synth";
        case TPModePet:      return @"Cursor pet, treats, purrs & Nyan Turbo squad";
        case TPModeSpectrum: return @"36-band OLED equalizer (Live Mic FFT + Touch)";
        case TPModeTools:    return @"Slide left/right! Media, Vol, Snap, CPU, Pomo";
        default:             return @"";
    }
}

NSString *TPModeSymbol(TPMode mode) {
    switch (mode) {
        case TPModePlasma:   return @"⚡";
        case TPModeWarp:     return @"✦";
        case TPModeFire:     return @"▲";
        case TPModeMatrix:   return @"⌘";
        case TPModeBeatbox:  return @"◈";
        case TPModePhysics:  return @"◉";
        case TPModeRunner:   return @"▸";
        case TPModeBlaster:  return @"◎";
        case TPModeSynth:    return @"♫";
        case TPModePet:      return @"★";
        case TPModeSpectrum: return @"ılı";
        case TPModeTools:    return @"⊞";
        default:             return @"◉";
    }
}

NSString *TPThemeName(TPTheme theme) {
    switch (theme) {
        case TPThemeCyberpunk: return @"Cyberpunk Neon";
        case TPThemeSolar:     return @"Solar Inferno";
        case TPThemeAurora:    return @"Aurora Borealis";
        case TPThemeVaporwave: return @"Vaporwave Sunset";
        case TPThemeMatrix:    return @"Matrix Emerald";
        default:               return @"Cyberpunk Neon";
    }
}

NSString *TPSynthScaleName(TPSynthScale scale) {
    switch (scale) {
        case TPSynthScalePentatonic:   return @"Cyber Pentatonic";
        case TPSynthScaleMajor9:       return @"Dreamy Major 9";
        case TPSynthScaleDarkPhrygian: return @"Dark Synthwave";
        case TPSynthScaleLofiBlues:    return @"Lofi Blues";
        case TPSynthScaleChromatic:    return @"Chromatic";
        default:                       return @"Cyber Pentatonic";
    }
}

static TPRGBA TPLerpRGBA(TPRGBA a, TPRGBA b, float t) {
    return (TPRGBA){
        TPLerpf(a.r, b.r, t),
        TPLerpf(a.g, b.g, t),
        TPLerpf(a.b, b.b, t),
        TPLerpf(a.a, b.a, t)
    };
}

TPRGBA TPThemeColor(TPTheme theme, float t, float alpha) {
    // Wrap or clamp t gracefully
    t = fmodf(t, 1.0f);
    if (t < 0.0f) t += 1.0f;

    static const TPRGBA palettes[TPThemeCount][4] = {
        // Cyberpunk Neon: Electric Cyan -> Deep Violet -> Hot Magenta -> Electric Cyan
        {
            {0.00f, 0.95f, 1.00f, 1.0f},
            {0.42f, 0.20f, 1.00f, 1.0f},
            {1.00f, 0.12f, 0.65f, 1.0f},
            {0.00f, 0.95f, 1.00f, 1.0f}
        },
        // Solar Inferno: Deep Crimson -> Blazing Orange -> Molten Gold -> White-Hot
        {
            {0.92f, 0.08f, 0.22f, 1.0f},
            {1.00f, 0.42f, 0.02f, 1.0f},
            {1.00f, 0.88f, 0.18f, 1.0f},
            {0.92f, 0.08f, 0.22f, 1.0f}
        },
        // Aurora Borealis: Mint Green -> Arctic Cyan -> Cobalt Blue -> Soft Violet
        {
            {0.10f, 1.00f, 0.62f, 1.0f},
            {0.05f, 0.82f, 0.98f, 1.0f},
            {0.35f, 0.40f, 1.00f, 1.0f},
            {0.10f, 1.00f, 0.62f, 1.0f}
        },
        // Vaporwave Sunset: Peach Pink -> Hot Coral -> Neon Purple -> Aqua
        {
            {1.00f, 0.42f, 0.62f, 1.0f},
            {0.82f, 0.22f, 0.96f, 1.0f},
            {0.18f, 0.88f, 0.95f, 1.0f},
            {1.00f, 0.42f, 0.62f, 1.0f}
        },
        // Matrix Emerald: Dark Emerald -> Neon Matrix Green -> Lime -> Teal
        {
            {0.00f, 0.68f, 0.28f, 1.0f},
            {0.15f, 1.00f, 0.35f, 1.0f},
            {0.55f, 1.00f, 0.65f, 1.0f},
            {0.00f, 0.68f, 0.28f, 1.0f}
        }
    };

    NSInteger idx = (theme >= 0 && theme < TPThemeCount) ? theme : 0;
    float scaled = t * 3.0f;
    int seg = (int)floorf(scaled);
    if (seg >= 3) seg = 2;
    float frac = scaled - (float)seg;
    TPRGBA c = TPLerpRGBA(palettes[idx][seg], palettes[idx][seg + 1], frac);
    c.a = alpha;
    return c;
}

NSColor *TPThemeNSColor(TPTheme theme, float t, float alpha) {
    TPRGBA c = TPThemeColor(theme, t, alpha);
    return [NSColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}

void TPDrawRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius) {
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    CGContextAddPath(ctx, path);
    CGPathRelease(path);
}

void TPDrawGlowCircle(CGContextRef ctx, CGFloat cx, CGFloat cy, CGFloat radius, TPRGBA color) {
    if (radius <= 0.1f || color.a <= 0.001f) return;
    // Fast 3-layer concentric additive-style glow (zero CGGradient alloc overhead per particle!)
    CGContextSetRGBFillColor(ctx, color.r, color.g, color.b, color.a * 0.22f);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - radius, cy - radius, radius * 2.0f, radius * 2.0f));

    CGFloat r2 = radius * 0.56f;
    CGContextSetRGBFillColor(ctx, color.r, color.g, color.b, color.a * 0.55f);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - r2, cy - r2, r2 * 2.0f, r2 * 2.0f));

    CGFloat r3 = radius * 0.24f;
    CGContextSetRGBFillColor(ctx,
                             TPLerpf(color.r, 1.0f, 0.6f),
                             TPLerpf(color.g, 1.0f, 0.6f),
                             TPLerpf(color.b, 1.0f, 0.6f),
                             TPClampf(color.a * 0.95f, 0.0f, 1.0f));
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - r3, cy - r3, r3 * 2.0f, r3 * 2.0f));
}

static NSFont *TPFontForSpec(CGFloat fontSize, NSFontWeight weight, BOOL monospaced) {
    static NSMutableDictionary<NSNumber *, NSFont *> *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    // Encode key cleanly: size*10 + weight bucket + mono bit
    int szKey = (int)lround(fontSize * 10.0);
    int wKey = (weight >= NSFontWeightHeavy) ? 4 : (weight >= NSFontWeightBold) ? 3 : (weight >= NSFontWeightSemibold) ? 2 : (weight >= NSFontWeightMedium) ? 1 : 0;
    NSNumber *key = @((szKey << 4) | (wKey << 1) | (monospaced ? 1 : 0));
    NSFont *f = cache[key];
    if (!f) {
        f = monospaced ? [NSFont monospacedSystemFontOfSize:fontSize weight:weight]
                       : [NSFont systemFontOfSize:fontSize weight:weight];
        if (f) cache[key] = f;
    }
    return f;
}

CGSize TPMeasureText(NSString *text, CGFloat fontSize, NSFontWeight weight, BOOL monospaced) {
    if (!text.length) return CGSizeZero;
    NSDictionary *attrs = @{
        NSFontAttributeName: TPFontForSpec(fontSize, weight, monospaced)
    };
    return [text sizeWithAttributes:attrs];
}

void TPDrawText(CGContextRef ctx, NSString *text, CGPoint origin, CGFloat fontSize, NSFontWeight weight, NSColor *color, BOOL monospaced) {
    if (!text.length) return;
    NSGraphicsContext *prev = [NSGraphicsContext currentContext];
    NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext setCurrentContext:nsCtx];
    NSDictionary *attrs = @{
        NSFontAttributeName: TPFontForSpec(fontSize, weight, monospaced),
        NSForegroundColorAttributeName: color ?: [NSColor whiteColor]
    };
    [text drawAtPoint:origin withAttributes:attrs];
    [NSGraphicsContext setCurrentContext:prev];
}

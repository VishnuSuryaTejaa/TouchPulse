#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, TPMode) {
    TPModePlasma = 0,
    TPModeWarp = 1,
    TPModeFire = 2,
    TPModeMatrix = 3,
    TPModeBeatbox = 4,
    TPModePhysics = 5,
    TPModeRunner = 6,
    TPModeBlaster = 7,
    TPModeSynth = 8,
    TPModePet = 9,
    TPModeSpectrum = 10,
    TPModeTools = 11,
    TPModeCount = 12
};

typedef NS_ENUM(NSInteger, TPTheme) {
    TPThemeCyberpunk = 0,
    TPThemeSolar = 1,
    TPThemeAurora = 2,
    TPThemeVaporwave = 3,
    TPThemeMatrix = 4,
    TPThemeCount = 5
};

typedef NS_ENUM(NSInteger, TPSynthScale) {
    TPSynthScalePentatonic = 0,
    TPSynthScaleMajor9 = 1,
    TPSynthScaleDarkPhrygian = 2,
    TPSynthScaleLofiBlues = 3,
    TPSynthScaleChromatic = 4,
    TPSynthScaleCount = 5
};

typedef struct {
    float r, g, b, a;
} TPRGBA;

typedef struct {
    BOOL active;
    uint64_t touchID;
    float x;          // 0..1 normalized across active canvas width
    float y;          // 0..1 normalized across height (0 = bottom, 1 = top)
    float prevX;
    float prevY;
    float startX;
    float startY;
    float vx;
    float vy;
    double startTime;
    int lastStringIndex;
} TPActiveTouch;

#define TP_MAX_TOUCHES 10
#define TP_MODE_PILL_WIDTH 34.0f

NS_INLINE float TPClampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

NS_INLINE float TPLerpf(float a, float b, float t) {
    return a + (b - a) * t;
}

NS_INLINE float TPRandf(void) {
    return (float)arc4random() / (float)UINT32_MAX;
}

NS_INLINE float TPRandRange(float lo, float hi) {
    return lo + (hi - lo) * TPRandf();
}

// Theme & mode metadata
NSString *TPModeName(TPMode mode);
NSString *TPModeSubtitle(TPMode mode);
NSString *TPModeSymbol(TPMode mode);
NSString *TPThemeName(TPTheme theme);
NSString *TPSynthScaleName(TPSynthScale scale);

TPRGBA TPThemeColor(TPTheme theme, float t, float alpha);
NSColor *TPThemeNSColor(TPTheme theme, float t, float alpha);

// CoreGraphics convenience helpers
void TPDrawRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius);
void TPDrawGlowCircle(CGContextRef ctx, CGFloat cx, CGFloat cy, CGFloat radius, TPRGBA color);
void TPDrawText(CGContextRef ctx, NSString *text, CGPoint origin, CGFloat fontSize, NSFontWeight weight, NSColor *color, BOOL monospaced);
CGSize TPMeasureText(NSString *text, CGFloat fontSize, NSFontWeight weight, BOOL monospaced);

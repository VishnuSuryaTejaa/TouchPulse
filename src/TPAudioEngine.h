#import <Foundation/Foundation.h>
#import "TPCommon.h"

#define TP_SPECTRUM_BANDS 36
#define TP_WAVEFORM_SAMPLES 64

typedef NS_ENUM(NSInteger, TPSFXType) {
    TPSFXClick = 0,
    TPSFXJump,
    TPSFXDoubleJump,
    TPSFXCoin,
    TPSFXExplosion,
    TPSFXLaserZap,
    TPSFXPetChirp,
    TPSFXSupernova,
    TPSFXPomodoroBell,
    TPSFXKick808,
    TPSFXSnare808,
    TPSFXHiHat,
    TPSFXAcid303,
    TPSFXTeslaZap,
    TPSFXFirework,
    TPSFXGlitch
};

@interface TPAudioEngine : NSObject

@property (nonatomic, assign) BOOL soundEnabled;
@property (nonatomic, assign) float masterVolume; // 0.0 .. 1.0
@property (nonatomic, assign, readonly) BOOL micActive;
@property (nonatomic, copy, nullable) void (^onMicStateChanged)(BOOL active, NSString *statusText);

+ (instancetype)shared;

- (void)startOutputIfNeeded;
- (void)stopAll;

// Polyphonic Neon Synth voice trigger (stereo pan: -1 left .. +1 right)
- (void)pluckSynthFreq:(float)freq pan:(float)pan velocity:(float)velocity waveform:(int)waveform;

// Sound effects
- (void)playSFX:(TPSFXType)type pan:(float)pan pitchScale:(float)pitchScale;

// Continuous Warp Black Hole sub-bass drone
- (void)setDroneLevel:(float)level freq:(float)freq pan:(float)pan;

// Live Microphone FFT Spectrum toggle
- (void)setMicEnabled:(BOOL)enabled;

// Read latest 36-band live mic FFT spectrum (0..1 per band)
- (void)copyMicSpectrum:(float *)outBands count:(int)count;

// Read latest 64-sample synth output waveform (-1..1) for visuals
- (void)copyOutputWaveform:(float *)outSamples count:(int)count;

// Musical scale helper
+ (float)frequencyForScale:(TPSynthScale)scale index:(int)index totalKeys:(int)totalKeys;
+ (NSString *)noteNameForScale:(TPSynthScale)scale index:(int)index;

@end

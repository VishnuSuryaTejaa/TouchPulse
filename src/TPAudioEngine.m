#import "TPAudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <os/lock.h>
#import <math.h>

#define MAX_VOICES 24
#define DELAY_BUF_SIZE 32768
#define FFT_LOG2N 9
#define FFT_SIZE (1 << FFT_LOG2N) // 512

typedef struct {
    BOOL active;
    int kind;          // 0=synth pluck, 1=sweep/sfx, 2=noise burst, 3=bell
    int waveform;      // 0=neon blend, 1=triangle, 2=square
    float freq;
    float targetFreq;
    float freqSlide;
    float phase;
    float phase2;
    float amp;
    float env;
    float attackRate;
    float decayRate;
    BOOL inAttack;
    float panL;
    float panR;
    float lpState;
    float lpCutoff;
    uint32_t rng;
} TPVoice;

@interface TPAudioEngine () {
    AVAudioEngine *_outEngine;
    AVAudioSourceNode *_sourceNode;
    double _sampleRate;

    os_unfair_lock _lock;
    TPVoice _voices[MAX_VOICES];

    // Stereo ping-pong delay line
    float _delayL[DELAY_BUF_SIZE];
    float _delayR[DELAY_BUF_SIZE];
    int _delayIdx;
    int _delayTailFrames;

    // Continuous Warp Drone
    float _droneTargetLevel;
    float _droneLevel;
    float _droneFreq;
    float _dronePan;
    float _dronePhase;
    float _dronePhase2;

    // Output waveform ring for visualization
    float _waveform[TP_WAVEFORM_SAMPLES];
    int _wavePos;
    int _waveDecim;

    // Live Mic Engine + vDSP FFT
    AVAudioEngine *_micEngine;
    FFTSetup _fftSetup;
    float _fftWindow[FFT_SIZE];
    float _fftReal[FFT_SIZE / 2];
    float _fftImag[FFT_SIZE / 2];
    float _micBands[TP_SPECTRUM_BANDS];
    os_unfair_lock _micLock;
    BOOL _micActive;
}
@end

@implementation TPAudioEngine

+ (instancetype)shared {
    static TPAudioEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TPAudioEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _micLock = OS_UNFAIR_LOCK_INIT;
        _soundEnabled = YES;
        _masterVolume = 0.72f;
        _sampleRate = 48000.0;
        _droneFreq = 58.0f;

        _fftSetup = vDSP_create_fftsetup(FFT_LOG2N, kFFTRadix2);
        vDSP_hann_window(_fftWindow, FFT_SIZE, vDSP_HANN_NORM);
    }
    return self;
}

- (void)dealloc {
    [self stopAll];
    if (_fftSetup) {
        vDSP_destroy_fftsetup(_fftSetup);
        _fftSetup = NULL;
    }
}

- (BOOL)micActive {
    return _micActive;
}

- (void)startOutputIfNeeded {
    if (_outEngine && _outEngine.isRunning) return;

    if (!_outEngine) {
        _outEngine = [[AVAudioEngine alloc] init];
        AVAudioFormat *outFmt = [_outEngine.outputNode inputFormatForBus:0];
        double sr = outFmt.sampleRate > 8000.0 ? outFmt.sampleRate : 48000.0;
        _sampleRate = sr;

        AVAudioFormat *stereoFmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sr channels:2];
        __unsafe_unretained TPAudioEngine *unretainedSelf = self;

        _sourceNode = [[AVAudioSourceNode alloc] initWithFormat:stereoFmt renderBlock:^OSStatus(
            BOOL * _Nonnull isSilence,
            const AudioTimeStamp * _Nonnull timestamp,
            AVAudioFrameCount frameCount,
            AudioBufferList * _Nonnull outputData) {
            return [unretainedSelf renderFrames:frameCount into:outputData isSilence:isSilence];
        }];

        [_outEngine attachNode:_sourceNode];
        [_outEngine connect:_sourceNode to:_outEngine.mainMixerNode format:stereoFmt];
    }

    NSError *err = nil;
    if (![_outEngine startAndReturnError:&err]) {
        NSLog(@"TouchPulse audio start warning: %@", err);
    }
}

- (void)stopAll {
    [self setMicEnabled:NO];
    if (_outEngine) {
        [_outEngine stop];
        _outEngine = nil;
        _sourceNode = nil;
    }
}

static inline float TPFastNoise(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return ((float)(x & 0xFFFF) / 32768.0f) - 1.0f;
}

- (OSStatus)renderFrames:(AVAudioFrameCount)frameCount
                    into:(AudioBufferList *)outputData
               isSilence:(BOOL *)isSilence {
    float *outL = (float *)outputData->mBuffers[0].mData;
    float *outR = (outputData->mNumberBuffers > 1) ? (float *)outputData->mBuffers[1].mData : outL;

    if (!_soundEnabled || _masterVolume <= 0.001f) {
        memset(outL, 0, frameCount * sizeof(float));
        if (outR != outL) memset(outR, 0, frameCount * sizeof(float));
        *isSilence = YES;
        return noErr;
    }

    float sr = (float)_sampleRate;
    float invSR = 1.0f / sr;
    float vol = _masterVolume * 0.55f;
    int delayTapL = (int)(sr * 0.215f);
    int delayTapR = (int)(sr * 0.310f);
    if (delayTapL >= DELAY_BUF_SIZE - 1) delayTapL = DELAY_BUF_SIZE - 2;
    if (delayTapR >= DELAY_BUF_SIZE - 1) delayTapR = DELAY_BUF_SIZE - 2;

    os_unfair_lock_lock(&_lock);

    // Fast idle bypass: zero DSP CPU when no voices, drone, or delay tail are sounding!
    BOOL anyVoice = (_droneLevel > 0.0008f || _droneTargetLevel > 0.0008f);
    if (!anyVoice) {
        for (int v = 0; v < MAX_VOICES; v++) {
            if (_voices[v].active) { anyVoice = YES; break; }
        }
    }
    if (!anyVoice && _delayTailFrames <= 0) {
        os_unfair_lock_unlock(&_lock);
        memset(outL, 0, frameCount * sizeof(float));
        if (outR != outL) memset(outR, 0, frameCount * sizeof(float));
        *isSilence = YES;
        return noErr;
    }
    if (anyVoice) {
        _delayTailFrames = (int)(sr * 2.2f);
    } else {
        _delayTailFrames -= (int)frameCount;
    }

    for (AVAudioFrameCount i = 0; i < frameCount; i++) {
        float dryL = 0.0f;
        float dryR = 0.0f;
        float wetSendL = 0.0f;
        float wetSendR = 0.0f;

        // 1. Render all active polyphonic voices
        for (int v = 0; v < MAX_VOICES; v++) {
            TPVoice *voice = &_voices[v];
            if (!voice->active) continue;

            // Envelope
            if (voice->inAttack) {
                voice->env += voice->attackRate;
                if (voice->env >= 1.0f) {
                    voice->env = 1.0f;
                    voice->inAttack = NO;
                }
            } else {
                voice->env *= voice->decayRate;
                if (voice->env < 0.0005f) {
                    voice->active = NO;
                    continue;
                }
            }

            // Pitch slide for SFX
            if (voice->freqSlide != 0.0f) {
                voice->freq += (voice->targetFreq - voice->freq) * voice->freqSlide;
            }

            float sample = 0.0f;
            float inc = voice->freq * invSR;
            voice->phase += inc;
            if (voice->phase >= 1.0f) voice->phase -= floorf(voice->phase);

            if (voice->kind == 0) {
                // Lush detuned neon synth voice (saw + sub-sine + slight detune)
                voice->phase2 += (voice->freq * 1.0055f) * invSR;
                if (voice->phase2 >= 1.0f) voice->phase2 -= floorf(voice->phase2);

                float saw1 = 2.0f * voice->phase - 1.0f;
                float saw2 = 2.0f * voice->phase2 - 1.0f;
                float sine = sinf(voice->phase * 2.0f * (float)M_PI);
                float raw = (saw1 * 0.32f + saw2 * 0.28f + sine * 0.55f);

                // Simple one-pole dynamic low-pass filter keyed to envelope
                float cutoff = TPClampf(voice->lpCutoff * (0.18f + 0.82f * voice->env), 0.02f, 0.72f);
                voice->lpState += cutoff * (raw - voice->lpState);
                sample = voice->lpState;
            } else if (voice->kind == 1) {
                // Clean arcade / chime tone
                if (voice->waveform == 2) {
                    sample = (voice->phase < 0.5f ? 0.55f : -0.55f);
                } else {
                    float tri = 4.0f * fabsf(voice->phase - 0.5f) - 1.0f;
                    float sinv = sinf(voice->phase * 2.0f * (float)M_PI);
                    sample = tri * 0.45f + sinv * 0.55f;
                }
            } else if (voice->kind == 2) {
                // Filtered noise burst (explosions / clicks)
                float n = TPFastNoise(&voice->rng);
                float sub = sinf(voice->phase * 2.0f * (float)M_PI) * 0.65f;
                voice->lpState += voice->lpCutoff * ((n * 0.75f + sub) - voice->lpState);
                sample = voice->lpState;
            } else {
                // Warm harmonic zen bell (fundamental + 2.756 overtone)
                voice->phase2 += (voice->freq * 2.756f) * invSR;
                if (voice->phase2 >= 1.0f) voice->phase2 -= floorf(voice->phase2);
                float f1 = sinf(voice->phase * 2.0f * (float)M_PI);
                float f2 = sinf(voice->phase2 * 2.0f * (float)M_PI) * 0.32f * voice->env;
                sample = (f1 + f2) * 0.75f;
            }

            float outS = sample * voice->env * voice->amp;
            dryL += outS * voice->panL;
            dryR += outS * voice->panR;

            if (voice->kind == 0 || voice->kind == 3) {
                wetSendL += outS * voice->panL;
                wetSendR += outS * voice->panR;
            }
        }

        // 2. Warp Black Hole smooth sub-bass drone
        _droneLevel += (_droneTargetLevel - _droneLevel) * 0.0015f;
        if (_droneLevel > 0.0008f) {
            _dronePhase += _droneFreq * invSR;
            if (_dronePhase >= 1.0f) _dronePhase -= 1.0f;
            _dronePhase2 += (_droneFreq * 1.503f) * invSR;
            if (_dronePhase2 >= 1.0f) _dronePhase2 -= 1.0f;

            float d = (sinf(_dronePhase * 2.0f * (float)M_PI) * 0.7f +
                       sinf(_dronePhase2 * 2.0f * (float)M_PI) * 0.3f) * _droneLevel * 0.42f;
            float p = TPClampf((_dronePan + 1.0f) * 0.5f, 0.0f, 1.0f);
            dryL += d * cosf(p * (float)M_PI_2);
            dryR += d * sinf(p * (float)M_PI_2);
        }

        // 3. Stereo ping-pong delay line
        int readL = (_delayIdx - delayTapL + DELAY_BUF_SIZE) & (DELAY_BUF_SIZE - 1);
        int readR = (_delayIdx - delayTapR + DELAY_BUF_SIZE) & (DELAY_BUF_SIZE - 1);
        float dL = _delayL[readL];
        float dR = _delayR[readR];

        _delayL[_delayIdx] = wetSendL + dR * 0.36f;
        _delayR[_delayIdx] = wetSendR + dL * 0.34f;
        _delayIdx = (_delayIdx + 1) & (DELAY_BUF_SIZE - 1);

        // Soft limiter (tanh)
        float mixL = tanhf((dryL + dL * 0.30f) * vol);
        float mixR = tanhf((dryR + dR * 0.30f) * vol);
        outL[i] = mixL;
        if (outR != outL) outR[i] = mixR;

        // Decimate into waveform visualization buffer (~every 12 samples)
        if (++_waveDecim >= 12) {
            _waveDecim = 0;
            _waveform[_wavePos] = (mixL + mixR) * 0.5f;
            _wavePos = (_wavePos + 1) % TP_WAVEFORM_SAMPLES;
        }
    }

    os_unfair_lock_unlock(&_lock);
    *isSilence = NO;
    return noErr;
}

- (TPVoice *)allocateVoiceLocked {
    int bestIdx = 0;
    float lowestEnv = 100.0f;
    for (int i = 0; i < MAX_VOICES; i++) {
        if (!_voices[i].active) return &_voices[i];
        if (_voices[i].env < lowestEnv) {
            lowestEnv = _voices[i].env;
            bestIdx = i;
        }
    }
    return &_voices[bestIdx];
}

static inline void TPSetPan(TPVoice *v, float pan) {
    float p = TPClampf((pan + 1.0f) * 0.5f, 0.0f, 1.0f);
    v->panL = cosf(p * (float)M_PI_2);
    v->panR = sinf(p * (float)M_PI_2);
}

- (void)pluckSynthFreq:(float)freq pan:(float)pan velocity:(float)velocity waveform:(int)waveform {
    if (!_soundEnabled) return;
    [self startOutputIfNeeded];
    float sr = (float)_sampleRate;

    os_unfair_lock_lock(&_lock);
    TPVoice *v = [self allocateVoiceLocked];
    memset(v, 0, sizeof(TPVoice));
    v->active = YES;
    v->kind = 0;
    v->waveform = waveform;
    v->freq = TPClampf(freq, 40.0f, 4000.0f);
    v->targetFreq = v->freq;
    v->amp = TPClampf(velocity, 0.05f, 1.0f) * 0.42f;
    v->env = 0.01f;
    v->inAttack = YES;
    v->attackRate = 1.0f / (sr * 0.008f);
    v->decayRate = powf(0.001f, 1.0f / (sr * 1.45f));
    v->lpCutoff = 0.44f;
    TPSetPan(v, pan);
    os_unfair_lock_unlock(&_lock);
}

- (void)playSFX:(TPSFXType)type pan:(float)pan pitchScale:(float)pitchScale {
    if (!_soundEnabled) return;
    [self startOutputIfNeeded];
    float sr = (float)_sampleRate;
    float pScale = pitchScale > 0.1f ? pitchScale : 1.0f;

    os_unfair_lock_lock(&_lock);
    TPVoice *v = [self allocateVoiceLocked];
    memset(v, 0, sizeof(TPVoice));
    v->active = YES;
    v->rng = arc4random() | 1u;
    v->env = 0.02f;
    v->inAttack = YES;
    TPSetPan(v, pan);

    switch (type) {
        case TPSFXClick:
            v->kind = 1;
            v->freq = 880.0f * pScale;
            v->targetFreq = 1320.0f * pScale;
            v->freqSlide = 0.003f;
            v->amp = 0.16f;
            v->attackRate = 1.0f / (sr * 0.002f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.06f));
            break;

        case TPSFXJump:
            v->kind = 1;
            v->waveform = 1;
            v->freq = 280.0f * pScale;
            v->targetFreq = 690.0f * pScale;
            v->freqSlide = 0.0016f;
            v->amp = 0.28f;
            v->attackRate = 1.0f / (sr * 0.004f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.18f));
            break;

        case TPSFXDoubleJump:
            v->kind = 1;
            v->waveform = 1;
            v->freq = 480.0f * pScale;
            v->targetFreq = 1120.0f * pScale;
            v->freqSlide = 0.0022f;
            v->amp = 0.30f;
            v->attackRate = 1.0f / (sr * 0.003f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.22f));
            break;

        case TPSFXCoin:
            v->kind = 1;
            v->freq = 987.77f * pScale;
            v->targetFreq = 1480.0f * pScale;
            v->freqSlide = 0.004f;
            v->amp = 0.26f;
            v->attackRate = 1.0f / (sr * 0.003f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.24f));
            break;

        case TPSFXLaserZap:
            v->kind = 1;
            v->waveform = 2;
            v->freq = 1280.0f * pScale;
            v->targetFreq = 260.0f * pScale;
            v->freqSlide = 0.0024f;
            v->amp = 0.22f;
            v->attackRate = 1.0f / (sr * 0.002f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.14f));
            break;

        case TPSFXExplosion:
            v->kind = 2;
            v->freq = 95.0f;
            v->targetFreq = 32.0f;
            v->freqSlide = 0.0008f;
            v->lpCutoff = 0.14f;
            v->amp = 0.45f;
            v->attackRate = 1.0f / (sr * 0.004f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.48f));
            break;

        case TPSFXSupernova:
            v->kind = 2;
            v->freq = 135.0f;
            v->targetFreq = 28.0f;
            v->freqSlide = 0.0005f;
            v->lpCutoff = 0.20f;
            v->amp = 0.50f;
            v->attackRate = 1.0f / (sr * 0.01f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.85f));
            break;

        case TPSFXPetChirp:
            v->kind = 1;
            v->freq = 640.0f * pScale;
            v->targetFreq = 1180.0f * pScale;
            v->freqSlide = 0.003f;
            v->amp = 0.22f;
            v->attackRate = 1.0f / (sr * 0.006f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.16f));
            break;

        case TPSFXPomodoroBell:
            v->kind = 3;
            v->freq = 528.0f * pScale;
            v->targetFreq = v->freq;
            v->amp = 0.42f;
            v->attackRate = 1.0f / (sr * 0.008f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 2.4f));
            break;

        case TPSFXKick808:
            // Punchy 808 sub-bass kick (rapid 165Hz -> 40Hz pitch sweep!)
            v->kind = 1;
            v->waveform = 1;
            v->freq = 165.0f * pScale;
            v->targetFreq = 38.0f;
            v->freqSlide = 0.0028f;
            v->amp = 0.62f;
            v->attackRate = 1.0f / (sr * 0.002f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.32f));
            break;

        case TPSFXSnare808:
            // Crisp noise snap + 195Hz snare body
            v->kind = 2;
            v->freq = 195.0f * pScale;
            v->targetFreq = 110.0f;
            v->freqSlide = 0.0015f;
            v->lpCutoff = 0.55f;
            v->amp = 0.42f;
            v->attackRate = 1.0f / (sr * 0.0015f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.17f));
            break;

        case TPSFXHiHat:
            // Short crisp high-frequency shimmer
            v->kind = 2;
            v->freq = 6400.0f;
            v->targetFreq = 6400.0f;
            v->lpCutoff = 0.92f;
            v->amp = 0.22f;
            v->attackRate = 1.0f / (sr * 0.001f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.055f));
            break;

        case TPSFXAcid303:
            // Squelchy cyberpunk acid synth bass
            v->kind = 0;
            v->freq = 92.5f * pScale;
            v->targetFreq = v->freq;
            v->lpCutoff = 0.68f;
            v->amp = 0.44f;
            v->attackRate = 1.0f / (sr * 0.004f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.28f));
            break;

        case TPSFXTeslaZap:
            // Crackling high-voltage electric arc
            v->kind = 2;
            v->freq = 940.0f * pScale;
            v->targetFreq = 280.0f;
            v->freqSlide = 0.003f;
            v->lpCutoff = 0.72f;
            v->amp = 0.28f;
            v->attackRate = 1.0f / (sr * 0.0015f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.14f));
            break;

        case TPSFXFirework:
            // Deep boom + crackle burst
            v->kind = 2;
            v->freq = 120.0f * pScale;
            v->targetFreq = 35.0f;
            v->freqSlide = 0.0009f;
            v->lpCutoff = 0.34f;
            v->amp = 0.46f;
            v->attackRate = 1.0f / (sr * 0.004f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.52f));
            break;

        case TPSFXGlitch:
            // Cyberpunk digital telemetry chirp
            v->kind = 1;
            v->waveform = 2;
            v->freq = 1480.0f * pScale;
            v->targetFreq = 620.0f * pScale;
            v->freqSlide = 0.006f;
            v->amp = 0.18f;
            v->attackRate = 1.0f / (sr * 0.0015f);
            v->decayRate = powf(0.001f, 1.0f / (sr * 0.085f));
            break;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)setDroneLevel:(float)level freq:(float)freq pan:(float)pan {
    if (level > 0.01f && _soundEnabled) {
        [self startOutputIfNeeded];
    }
    os_unfair_lock_lock(&_lock);
    _droneTargetLevel = TPClampf(level, 0.0f, 1.0f);
    _droneFreq = TPClampf(freq, 35.0f, 320.0f);
    _dronePan = TPClampf(pan, -1.0f, 1.0f);
    os_unfair_lock_unlock(&_lock);
}

#pragma mark - Live Microphone FFT Capture

- (void)setMicEnabled:(BOOL)enabled {
    if (!enabled) {
        if (_micEngine) {
            [_micEngine.inputNode removeTapOnBus:0];
            [_micEngine stop];
            _micEngine = nil;
        }
        _micActive = NO;
        os_unfair_lock_lock(&_micLock);
        memset(_micBands, 0, sizeof(_micBands));
        os_unfair_lock_unlock(&_micLock);
        if (self.onMicStateChanged) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.onMicStateChanged(NO, @"Mic Off (Interactive Touch Beat Mode)");
            });
        }
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        [self startMicCaptureNow];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [weakSelf startMicCaptureNow];
                } else {
                    if (weakSelf.onMicStateChanged) {
                        weakSelf.onMicStateChanged(NO, @"Mic permission denied — using Touch Beat mode");
                    }
                }
            });
        }];
    } else {
        if (self.onMicStateChanged) {
            self.onMicStateChanged(NO, @"Enable Microphone for TouchPulse in System Settings");
        }
    }
}

- (void)startMicCaptureNow {
    if (_micEngine && _micEngine.isRunning) return;
    _micEngine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *input = _micEngine.inputNode;
    AVAudioFormat *fmt = [input outputFormatForBus:0];
    if (!fmt || fmt.sampleRate <= 0 || fmt.channelCount == 0) {
        _micEngine = nil;
        if (self.onMicStateChanged) {
            self.onMicStateChanged(NO, @"No audio input device available");
        }
        return;
    }

    __unsafe_unretained TPAudioEngine *unretainedSelf = self;
    [input installTapOnBus:0 bufferSize:FFT_SIZE format:fmt block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [unretainedSelf processMicBuffer:buffer];
    }];

    NSError *err = nil;
    if ([_micEngine startAndReturnError:&err]) {
        _micActive = YES;
        if (self.onMicStateChanged) {
            self.onMicStateChanged(YES, @"Live Microphone FFT Active");
        }
    } else {
        [_micEngine.inputNode removeTapOnBus:0];
        _micEngine = nil;
        _micActive = NO;
        if (self.onMicStateChanged) {
            self.onMicStateChanged(NO, @"Could not start mic capture");
        }
    }
}

- (void)processMicBuffer:(AVAudioPCMBuffer *)buffer {
    if (!buffer.floatChannelData || buffer.frameLength < FFT_SIZE) return;
    const float *samples = buffer.floatChannelData[0];

    float windowed[FFT_SIZE];
    vDSP_vmul(samples, 1, _fftWindow, 1, windowed, 1, FFT_SIZE);

    DSPSplitComplex split = { _fftReal, _fftImag };
    vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, FFT_SIZE / 2);
    vDSP_fft_zrip(_fftSetup, &split, 1, FFT_LOG2N, FFT_FORWARD);

    float mags[FFT_SIZE / 2];
    vDSP_zvmags(&split, 1, mags, 1, FFT_SIZE / 2);

    float localBands[TP_SPECTRUM_BANDS];
    // Logarithmic bin grouping across 1..(FFT_SIZE/2 - 1)
    const int maxBin = (FFT_SIZE / 2) - 1;
    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        float f0 = powf((float)maxBin, (float)b / (float)TP_SPECTRUM_BANDS);
        float f1 = powf((float)maxBin, (float)(b + 1) / (float)TP_SPECTRUM_BANDS);
        int bin0 = MAX(1, (int)floorf(f0));
        int bin1 = MAX(bin0 + 1, MIN(maxBin, (int)ceilf(f1)));
        float sum = 0.0f;
        for (int k = bin0; k < bin1; k++) {
            sum += sqrtf(mags[k]);
        }
        float avg = sum / (float)(bin1 - bin0);
        // Gentle perceptual log scaling with slight treble boost
        float trebleBoost = 1.0f + ((float)b / (float)TP_SPECTRUM_BANDS) * 1.4f;
        float norm = log1pf(avg * 3.8f * trebleBoost) / 3.4f;
        localBands[b] = TPClampf(norm, 0.0f, 1.0f);
    }

    os_unfair_lock_lock(&_micLock);
    for (int b = 0; b < TP_SPECTRUM_BANDS; b++) {
        _micBands[b] = TPLerpf(_micBands[b], localBands[b], 0.55f);
    }
    os_unfair_lock_unlock(&_micLock);
}

- (void)copyMicSpectrum:(float *)outBands count:(int)count {
    int n = MIN(count, TP_SPECTRUM_BANDS);
    os_unfair_lock_lock(&_micLock);
    memcpy(outBands, _micBands, n * sizeof(float));
    os_unfair_lock_unlock(&_micLock);
}

- (void)copyOutputWaveform:(float *)outSamples count:(int)count {
    int n = MIN(count, TP_WAVEFORM_SAMPLES);
    os_unfair_lock_lock(&_lock);
    int start = (_wavePos - n + TP_WAVEFORM_SAMPLES) % TP_WAVEFORM_SAMPLES;
    for (int i = 0; i < n; i++) {
        outSamples[i] = _waveform[(start + i) % TP_WAVEFORM_SAMPLES];
    }
    os_unfair_lock_unlock(&_lock);
}

#pragma mark - Musical Scales

static int TPMidiForScale(TPSynthScale scale, int index) {
    // 18 notes starting around C3/D3
    static const int pentatonic[] = { 48, 51, 53, 55, 58, 60, 63, 65, 67, 70, 72, 75, 77, 79, 82, 84, 87, 89 };
    static const int major9[]     = { 48, 50, 52, 55, 57, 59, 60, 62, 64, 67, 69, 71, 72, 74, 76, 79, 81, 83 };
    static const int phrygian[]   = { 50, 51, 54, 55, 57, 58, 61, 62, 63, 66, 67, 69, 70, 73, 74, 75, 78, 79 };
    static const int blues[]      = { 48, 51, 53, 54, 55, 58, 60, 63, 65, 66, 67, 70, 72, 75, 77, 78, 79, 82 };
    int idx = MAX(0, MIN(17, index));
    switch (scale) {
        case TPSynthScalePentatonic:   return pentatonic[idx];
        case TPSynthScaleMajor9:       return major9[idx];
        case TPSynthScaleDarkPhrygian: return phrygian[idx];
        case TPSynthScaleLofiBlues:    return blues[idx];
        case TPSynthScaleChromatic:    return 54 + idx;
        default:                       return pentatonic[idx];
    }
}

+ (float)frequencyForScale:(TPSynthScale)scale index:(int)index totalKeys:(int)totalKeys {
    int midi = TPMidiForScale(scale, index);
    return 440.0f * powf(2.0f, ((float)midi - 69.0f) / 12.0f);
}

+ (NSString *)noteNameForScale:(TPSynthScale)scale index:(int)index {
    static NSString *const names[12] = {
        @"C", @"C#", @"D", @"Eb", @"E", @"F", @"F#", @"G", @"Ab", @"A", @"Bb", @"B"
    };
    int midi = TPMidiForScale(scale, index);
    int oct = (midi / 12) - 1;
    return [NSString stringWithFormat:@"%@%d", names[midi % 12], oct];
}

@end

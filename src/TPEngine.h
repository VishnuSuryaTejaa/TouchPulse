#import "TPAudioEngine.h"
#import "TPCommon.h"
#import <AppKit/AppKit.h>

#define TP_WAVE_N 140
#define TP_MAX_PARTICLES 320
#define TP_MAX_STARS 220
#define TP_MAX_OBSTACLES 24
#define TP_MAX_TARGETS 20
#define TP_MAX_BOLTS 16
#define TP_SYNTH_KEYS 18
#define TP_PET_TRAIL_N 48

// New Chaos Mode Constants
#define TP_MAX_BALL_LIGHTNING 8
#define TP_FIRE_W 160
#define TP_FIRE_H 14
#define TP_MAX_ROCKETS 10
#define TP_MATRIX_COLS 72
#define TP_BEAT_STEPS 16
#define TP_BEAT_TRACKS 4
#define TP_PHYS_ORBS 78

typedef struct {
  BOOL active;
  float x, y;   // normalized x (0..1), pixel y (0..30)
  float vx, vy; // normalized vx/s, pixel vy/s
  float life;
  float maxLife;
  float size;
  float hue;
  int kind; // 0=glow orb, 1=spark line, 2=heart, 3=pixel square
} TPParticle;

typedef struct {
  BOOL active;
  float x, y; // normalized x (0..1), pixel y (0..30)
  float vx, vy;
  float life;
  float hue;
  float radius;
} TPBallLightning;

typedef struct {
  float x, y, z;
  float px, py;
  float hue;
  float speed;
} TPStar;

typedef struct {
  BOOL active;
  float x, y; // normalized x (0..1), pixel y (0..30)
  float vx, vy;
  float fuse;
  float hue;
} TPFireworkRocket;

typedef struct {
  float y; // head row in 0..30 (falls downward from 30 -> 0)
  float speed;
  int glyphSeed;
  float length;
  float glitch; // red/cyan breach distortion 0..1
} TPMatrixCol;

typedef struct {
  float x, y; // normalized x (0..1), pixel y (0..30)
  float vx, vy;
  float radius;
  float hue;
  float energy;
} TPPhysOrb;

typedef struct {
  BOOL active;
  float x;
  float width;
  float height;
  float yBase;
  int kind; // 0=spike, 1=double hurdle, 2=drone, 3=gold orb
  BOOL collected;
  float phase;
} TPRunnerObstacle;

typedef struct {
  BOOL active;
  float x;
  float y;
  float vx;
  float age;
  float lifetime;
  float hue;
  int kind;
} TPBlasterTarget;

typedef struct {
  BOOL active;
  float x0, y0;
  float x1, y1;
  float life;
  float hue;
} TPLaserBolt;

@interface TPEngine : NSObject {
@public
  // Core configuration ivars exposed to mode categories
  TPMode _mode;
  TPTheme _theme;
  TPSynthScale _synthScale;
  float _speedScale;
  BOOL _showModePill;
  BOOL _mouseReactive;

  // Shared timing & interaction
  double _time;
  float _dt;
  float _mouseNormX;
  TPActiveTouch _touches[TP_MAX_TOUCHES];

  // Mode HUD toast
  NSString *_hudTitle;
  NSString *_hudSub;
  double _hudUntil;
  float _modeFlash;

  // Shared particle system
  TPParticle _particles[TP_MAX_PARTICLES];

  // Mode 0: Chaos Plasma + Ball Lightning
  float _waveU[TP_WAVE_N];
  float _waveV[TP_WAVE_N];
  float _plasmaHeat[TP_WAVE_N];
  TPBallLightning _ballLightning[TP_MAX_BALL_LIGHTNING];

  // Mode 1: Black Hole Collider (supports Binary Black Holes + Big Bang!)
  TPStar _stars[TP_MAX_STARS];
  BOOL _bhActive;
  float _bhX, _bhY, _bhMass;
  BOOL _bh2Active;
  float _bh2X, _bh2Y, _bh2Mass;
  float _supernovaAge;
  float _supernovaX, _supernovaY;
  BOOL _supernovaBigBang;

  // Mode 2: Inferno Cellular Fire & Fireworks
  float _fireGrid[TP_FIRE_H][TP_FIRE_W];
  float _fireWind;
  TPFireworkRocket _rockets[TP_MAX_ROCKETS];
  float _autoRocketTimer;

  // Mode 3: Matrix Digital Rain + Hacker Breach
  TPMatrixCol _matrixCols[TP_MATRIX_COLS];
  float _breachTimer;
  NSString *_breachBanner;
  float _breachX;

  // Mode 4: 808 Beatbox 16-Step Sequencer
  BOOL _beatPlaying;
  BOOL _beatGrid[TP_BEAT_TRACKS]
                [TP_BEAT_STEPS]; // 0=Kick, 1=Snare, 2=HiHat, 3=Acid303
  int _beatCurrentStep;
  float _beatStepTimer;
  float _beatStepGlow[TP_BEAT_STEPS];
  float _beatKickFlash;

  // Mode 5: Mercury Vortex Physics Sandbox
  TPPhysOrb _orbs[TP_PHYS_ORBS];
  float _vortexCharge;

  // Mode 6: Cyber Runner
  BOOL _runnerGameOver;
  float _runnerY, _runnerVY;
  int _runnerJumpsLeft;
  float _runnerSpeed, _runnerScore, _runnerDist, _runnerLegPhase,
      _runnerSpawnTimer, _runnerFlash;
  int _runnerHighScore;
  TPRunnerObstacle _obstacles[TP_MAX_OBSTACLES];

  // Mode 7: Laser Blaster
  BOOL _blasterGameOver;
  int _blasterScore, _blasterHighScore, _blasterCombo, _blasterMaxCombo,
      _blasterShield;
  float _blasterOverdrive, _blasterSpawnTimer, _blasterShake;
  TPBlasterTarget _targets[TP_MAX_TARGETS];
  TPLaserBolt _bolts[TP_MAX_BOLTS];

  // Mode 8: Neon Synth
  float _synthAmp[TP_SYNTH_KEYS];
  float _synthPhase[TP_SYNTH_KEYS];
  float _synthGlow[TP_SYNTH_KEYS];

  // Mode 9: Cyber Nyan Squad
  float _petX, _petY, _petVX, _petVY;
  int _petFacing;
  float _petWalkPhase, _petIdleTime, _petTurboTimer, _petHappyTimer,
      _petFlipAngle;
  BOOL _treatActive;
  float _treatX, _treatY, _treatVY;
  float _petTrailX[TP_PET_TRAIL_N];
  float _petTrailY[TP_PET_TRAIL_N];
  int _petTrailHead;

  // Mode 10: Spectrum Pulse
  float _specBars[TP_SPECTRUM_BANDS];
  float _specPeaks[TP_SPECTRUM_BANDS];
  float _specPeakVel[TP_SPECTRUM_BANDS];
  float _specTouchBoost[TP_SPECTRUM_BANDS];
  float _specPhase;

  // Mode 11: Slidable Power HUD & Handy Deck
  BOOL _pomoRunning;
  double _pomoRemaining, _pomoTotal, _lastPomoTap;
  float _pomoFlash;
  CGFloat _hudScrollX;
  CGFloat _hudScrollVel;
  CGFloat _hudMaxScroll;
  BOOL _hudIsDragging;
  BOOL _hudDidSlide;
  CGFloat _hudDragStartX;
  CGFloat _hudLastDragX;
  CGFloat _hudDragStartScroll;
  double _hudLastDragTime;
  uint64_t _hudActiveTouchID;
  CGFloat _hudTapFeedbackX;
  float _hudTapFeedbackLife;

  // Virtual-coordinate hit rects inside the scrollable Power HUD deck
  CGRect _hitMediaPrev;
  CGRect _hitMediaPlay;
  CGRect _hitMediaNext;
  CGRect _hitVolBar;
  CGRect _hitMuteBtn;
  CGRect _hitSnapBtn;
  CGRect _hitAwakeBtn;
  CGRect _hitLockBtn;
  CGRect _hitPomoBtn;
  CGRect _hitAppTerm;
  CGRect _hitAppFinder;
  CGRect _hitAppBrowser;
  CGRect _hitAppNotes;
  CGFloat _lastCanvasWidth;
}

@property(nonatomic, assign) TPMode mode;
@property(nonatomic, assign) TPTheme theme;
@property(nonatomic, assign) TPSynthScale synthScale;
@property(nonatomic, assign) float speedScale;
@property(nonatomic, assign) BOOL showModePill;
@property(nonatomic, assign) BOOL mouseReactive;
@property(nonatomic, assign, readonly) BOOL isRunning;
@property(nonatomic, copy, nullable) void (^onStateChanged)(void);

+ (instancetype)shared;

- (void)registerDisplayView:(NSView *)view;
- (void)unregisterDisplayView:(NSView *)view;
- (void)updateRunningState;

- (void)cycleNextMode;
- (void)cyclePrevMode;
- (void)cycleNextTheme;
- (void)showToast:(NSString *)title subtitle:(NSString *)sub;

- (void)handleTouchBeganID:(uint64_t)touchID
                     point:(CGPoint)pt
                    inSize:(CGSize)size;
- (void)handleTouchMovedID:(uint64_t)touchID
                     point:(CGPoint)pt
                    inSize:(CGSize)size;
- (void)handleTouchEndedID:(uint64_t)touchID
                     point:(CGPoint)pt
                    inSize:(CGSize)size;
- (void)cancelAllTouches;

- (void)renderInContext:(CGContextRef)ctx size:(CGSize)size;

- (void)spawnParticleX:(float)normX
                     y:(float)py
                    vx:(float)vx
                    vy:(float)vy
                  life:(float)life
                  size:(float)size
                   hue:(float)hue
                  kind:(int)kind;
- (void)clearParticles;

@end

// Mode categories
@interface TPEngine (VisualModes)
- (void)initVisualModes;
- (void)stepPlasma:(float)dt;
- (void)renderPlasma:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchPlasmaBegan:(float)nx y:(float)ny;
- (void)touchPlasmaMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy;
- (void)touchPlasmaEnded:(float)nx y:(float)ny vx:(float)vx vy:(float)vy;

- (void)stepWarp:(float)dt;
- (void)renderWarp:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchWarpEnded:(float)nx y:(float)ny;

- (void)stepPet:(float)dt;
- (void)renderPet:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchPetBegan:(float)nx y:(float)ny;
- (void)touchPetMoved:(float)nx y:(float)ny;
- (void)triggerPetTurbo;

- (void)stepSpectrum:(float)dt;
- (void)renderSpectrum:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchSpectrumAt:(float)nx y:(float)ny strong:(BOOL)strong;
@end

@interface TPEngine (ChaosModes)
- (void)initChaosModes;

- (void)stepFire:(float)dt;
- (void)renderFire:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchFireBegan:(float)nx y:(float)ny;
- (void)touchFireMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy;

- (void)stepMatrix:(float)dt;
- (void)renderMatrix:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchMatrixBegan:(float)nx y:(float)ny;
- (void)touchMatrixMoved:(float)nx y:(float)ny;

- (void)randomizeBeatbox;
- (void)toggleBeatboxPlaying;
- (void)stepBeatbox:(float)dt;
- (void)renderBeatbox:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchBeatboxBegan:(float)nx y:(float)ny;

- (void)stepPhysics:(float)dt;
- (void)renderPhysics:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchPhysicsBegan:(float)nx y:(float)ny;
- (void)touchPhysicsMoved:(float)nx y:(float)ny vx:(float)vx vy:(float)vy;
- (void)touchPhysicsEnded:(float)nx y:(float)ny;
@end

@interface TPEngine (ArcadeModes)
- (void)resetRunner;
- (void)stepRunner:(float)dt;
- (void)renderRunner:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchRunnerBegan:(float)nx y:(float)ny;

- (void)resetBlaster;
- (void)stepBlaster:(float)dt;
- (void)renderBlaster:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchBlasterBegan:(float)nx y:(float)ny;

- (void)stepSynth:(float)dt;
- (void)renderSynth:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchSynthAt:(TPActiveTouch *)touch isNew:(BOOL)isNew;
@end

@interface TPEngine (ToolsMode)
- (void)togglePomodoro;
- (void)resetPomodoro;
- (void)stepTools:(float)dt;
- (void)renderTools:(CGContextRef)ctx rect:(CGRect)r;
- (void)touchToolsBeganID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r;
- (void)touchToolsMovedID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r;
- (void)touchToolsEndedID:(uint64_t)tid point:(CGPoint)pt rect:(CGRect)r;
@end

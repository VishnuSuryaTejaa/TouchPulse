#import <Foundation/Foundation.h>

#define TP_CPU_HISTORY_COUNT 40
#define TP_MAX_CPU_CORES 32

@interface TPSystemMonitor : NSObject

@property (nonatomic, assign, readonly) float cpuUsage;      // 0.0 .. 1.0
@property (nonatomic, assign, readonly) int cpuCoreCount;
@property (nonatomic, assign, readonly) float ramUsage;      // 0.0 .. 1.0
@property (nonatomic, assign, readonly) float ramUsedGB;
@property (nonatomic, assign, readonly) float ramTotalGB;
@property (nonatomic, assign, readonly) float diskFreeGB;
@property (nonatomic, assign, readonly) float diskTotalGB;
@property (nonatomic, assign, readonly) int batteryPercent;  // 0 .. 100
@property (nonatomic, assign, readonly) BOOL batteryCharging;
@property (nonatomic, assign, readonly) BOOL batteryPluggedIn;
@property (nonatomic, assign, readonly) int batteryMinutesLeft; // -1 if unknown
@property (nonatomic, assign, readonly) double netDownBytesPerSec;
@property (nonatomic, assign, readonly) double netUpBytesPerSec;
@property (nonatomic, assign, readonly) BOOL keepAwakeActive;

// Native CoreAudio System Volume & Mute
@property (nonatomic, assign, readonly) float systemVolume;  // 0.0 .. 1.0
@property (nonatomic, assign, readonly) BOOL systemMuted;

// Live Now Playing (Spotify / Apple Music)
@property (nonatomic, copy, readonly) NSString *nowPlayingTrack;
@property (nonatomic, copy, readonly) NSString *nowPlayingArtist;
@property (nonatomic, copy, readonly) NSString *nowPlayingApp;
@property (nonatomic, assign, readonly) BOOL nowPlayingIsPlaying;

+ (instancetype)shared;

- (void)startPolling;
- (void)stopPolling;

- (void)toggleKeepAwake;
- (void)setKeepAwake:(BOOL)enabled;

// System Volume & Mute
- (void)setSystemVolume:(float)vol;
- (void)stepSystemVolume:(float)delta;
- (void)toggleSystemMute;

// Media controls (Spotify / Apple Music)
- (void)mediaPlayPause;
- (void)mediaNext;
- (void)mediaPrevious;

// Handy Mac Utilities
- (void)takeClipboardScreenshot;
- (void)lockScreenNow;
- (void)launchAppWithBundleID:(NSString *)bundleID fallbackPath:(NSString *)path;

- (void)copyCPUHistory:(float *)outBuffer count:(int)count;
- (void)copyPerCoreCPU:(float *)outCores maxCount:(int)maxCount;
- (NSString *)formattedRate:(double)bytesPerSec;

@end

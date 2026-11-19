#import "TPSystemMonitor.h"
#import "TPCommon.h"
#import <AppKit/AppKit.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/mach_host.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dlfcn.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

@interface TPSystemMonitor () {
    NSTimer *_timer;
    uint64_t _prevTotalTicks;
    uint64_t _prevIdleTicks;
    uint64_t _prevCoreTotal[TP_MAX_CPU_CORES];
    uint64_t _prevCoreIdle[TP_MAX_CPU_CORES];
    float _perCoreUsage[TP_MAX_CPU_CORES];
    BOOL _hasPrevCPU;

    uint64_t _prevRxBytes;
    uint64_t _prevTxBytes;
    double _prevNetTime;
    BOOL _hasPrevNet;

    float _cpuHistory[TP_CPU_HISTORY_COUNT];
    int _cpuHistPos;

    IOPMAssertionID _sleepAssertionID;
    BOOL _hasAssertion;

    NSString *_nowPlayingTrack;
    NSString *_nowPlayingArtist;
    NSString *_nowPlayingApp;
    BOOL _nowPlayingIsPlaying;
}
@end

@implementation TPSystemMonitor

+ (instancetype)shared {
    static TPSystemMonitor *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[TPSystemMonitor alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        uint64_t memSize = 0;
        size_t len = sizeof(memSize);
        if (sysctlbyname("hw.memsize", &memSize, &len, NULL, 0) == 0 && memSize > 0) {
            _ramTotalGB = (float)((double)memSize / (1024.0 * 1024.0 * 1024.0));
        } else {
            _ramTotalGB = 16.0f;
        }
        _batteryPercent = 100;
        _batteryMinutesLeft = -1;
        _nowPlayingTrack = @"";
        _nowPlayingArtist = @"";
        _nowPlayingApp = @"";

        // Listen for instant zero-CPU Spotify & Apple Music playback notifications!
        NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
        [dnc addObserver:self selector:@selector(onSpotifyChanged:)
                    name:@"com.spotify.client.PlaybackStateChanged" object:nil];
        [dnc addObserver:self selector:@selector(onMusicChanged:)
                    name:@"com.apple.Music.playerInfo" object:nil];

        [self sampleAll];
    }
    return self;
}

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [self stopPolling];
    [self setKeepAwake:NO];
}

- (void)startPolling {
    if (_timer) return;
    [self sampleAll];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf sampleAll];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopPolling {
    [_timer invalidate];
    _timer = nil;
}

- (void)sampleAll {
    [self sampleCPU];
    [self sampleRAM];
    [self sampleDisk];
    [self sampleBattery];
    [self sampleNetwork];
    [self sampleVolume];
}

- (void)sampleCPU {
    natural_t numCPUs = 0;
    processor_info_array_t cpuInfo = NULL;
    mach_msg_type_number_t numCpuInfo = 0;

    kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo);
    if (err != KERN_SUCCESS || !cpuInfo) return;

    _cpuCoreCount = MIN((int)numCPUs, TP_MAX_CPU_CORES);
    uint64_t totalTicks = 0;
    uint64_t idleTicks = 0;

    for (natural_t i = 0; i < numCPUs; i++) {
        uint64_t user   = (uint64_t)cpuInfo[CPU_STATE_MAX * i + CPU_STATE_USER];
        uint64_t sys    = (uint64_t)cpuInfo[CPU_STATE_MAX * i + CPU_STATE_SYSTEM];
        uint64_t nice   = (uint64_t)cpuInfo[CPU_STATE_MAX * i + CPU_STATE_NICE];
        uint64_t idle   = (uint64_t)cpuInfo[CPU_STATE_MAX * i + CPU_STATE_IDLE];
        uint64_t cTot   = user + sys + nice + idle;
        totalTicks += cTot;
        idleTicks  += idle;

        if ((int)i < TP_MAX_CPU_CORES) {
            if (_hasPrevCPU && cTot > _prevCoreTotal[i]) {
                uint64_t dtot = cTot - _prevCoreTotal[i];
                uint64_t didl = (idle >= _prevCoreIdle[i]) ? (idle - _prevCoreIdle[i]) : 0;
                _perCoreUsage[i] = TPClampf(1.0f - (float)didl / (float)dtot, 0.0f, 1.0f);
            }
            _prevCoreTotal[i] = cTot;
            _prevCoreIdle[i]  = idle;
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo, sizeof(integer_t) * numCpuInfo);

    if (_hasPrevCPU && totalTicks > _prevTotalTicks) {
        uint64_t dTotal = totalTicks - _prevTotalTicks;
        uint64_t dIdle  = (idleTicks >= _prevIdleTicks) ? (idleTicks - _prevIdleTicks) : 0;
        float usage = 1.0f - ((float)dIdle / (float)dTotal);
        _cpuUsage = TPClampf(usage, 0.0f, 1.0f);
        _cpuHistory[_cpuHistPos] = _cpuUsage;
        _cpuHistPos = (_cpuHistPos + 1) % TP_CPU_HISTORY_COUNT;
    }

    _prevTotalTicks = totalTicks;
    _prevIdleTicks = idleTicks;
    _hasPrevCPU = YES;
}

- (void)sampleRAM {
    vm_statistics64_data_t vmStat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStat, &count) == KERN_SUCCESS) {
        double pageSize = (double)vm_kernel_page_size;
        uint64_t usedPages = (uint64_t)vmStat.active_count +
                             (uint64_t)vmStat.wire_count +
                             (uint64_t)vmStat.compressor_page_count;
        double usedBytes = (double)usedPages * pageSize;
        _ramUsedGB = (float)(usedBytes / (1024.0 * 1024.0 * 1024.0));
        _ramUsage = TPClampf(_ramTotalGB > 0.1f ? (_ramUsedGB / _ramTotalGB) : 0.0f, 0.0f, 1.0f);
    }
}

- (void)sampleDisk {
    struct statfs st;
    if (statfs("/", &st) == 0) {
        double bsize = (double)st.f_bsize;
        _diskFreeGB  = (float)(((double)st.f_bavail * bsize) / (1000.0 * 1000.0 * 1000.0));
        _diskTotalGB = (float)(((double)st.f_blocks * bsize) / (1000.0 * 1000.0 * 1000.0));
    }
}

- (void)sampleBattery {
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) return;
    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (sources) {
        CFIndex n = CFArrayGetCount(sources);
        for (CFIndex i = 0; i < n; i++) {
            CFTypeRef ps = CFArrayGetValueAtIndex(sources, i);
            NSDictionary *desc = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(blob, ps);
            if (!desc) continue;
            NSNumber *cur = desc[@kIOPSCurrentCapacityKey];
            NSNumber *max = desc[@kIOPSMaxCapacityKey];
            if (cur && max && max.intValue > 0) {
                _batteryPercent = (int)lround((cur.doubleValue / max.doubleValue) * 100.0);
                _batteryCharging = [desc[@kIOPSIsChargingKey] boolValue];
                NSString *state = desc[@kIOPSPowerSourceStateKey];
                _batteryPluggedIn = [state isEqualToString:@kIOPSACPowerValue];
                NSNumber *tte = _batteryCharging ? desc[@kIOPSTimeToFullChargeKey] : desc[@kIOPSTimeToEmptyKey];
                _batteryMinutesLeft = (tte && tte.intValue > 0 && tte.intValue < 6000) ? tte.intValue : -1;
                break;
            }
        }
        CFRelease(sources);
    }
    CFRelease(blob);
}

- (void)sampleNetwork {
    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0 || !addrs) return;

    uint64_t rxTotal = 0;
    uint64_t txTotal = 0;
    for (struct ifaddrs *cursor = addrs; cursor != NULL; cursor = cursor->ifa_next) {
        if (!cursor->ifa_addr || cursor->ifa_addr->sa_family != AF_LINK) continue;
        if (cursor->ifa_flags & IFF_LOOPBACK) continue;
        if (!(cursor->ifa_flags & IFF_UP)) continue;
        struct if_data *data = (struct if_data *)cursor->ifa_data;
        if (!data) continue;
        rxTotal += data->ifi_ibytes;
        txTotal += data->ifi_obytes;
    }
    freeifaddrs(addrs);

    double now = CACurrentMediaTime();
    if (_hasPrevNet && now > _prevNetTime) {
        double dt = now - _prevNetTime;
        double dRx = (rxTotal >= _prevRxBytes) ? (double)(rxTotal - _prevRxBytes) : 0.0;
        double dTx = (txTotal >= _prevTxBytes) ? (double)(txTotal - _prevTxBytes) : 0.0;
        _netDownBytesPerSec = dRx / dt;
        _netUpBytesPerSec = dTx / dt;
    }
    _prevRxBytes = rxTotal;
    _prevTxBytes = txTotal;
    _prevNetTime = now;
    _hasPrevNet = YES;
}

#pragma mark - Native CoreAudio System Volume & Mute

static AudioDeviceID TPDefaultOutputDevice(void) {
    AudioDeviceID dev = kAudioObjectUnknown;
    UInt32 sz = sizeof(dev);
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &sz, &dev);
    return dev;
}

- (void)sampleVolume {
    AudioDeviceID dev = TPDefaultOutputDevice();
    if (dev == kAudioObjectUnknown) return;

    Float32 vol = _systemVolume;
    UInt32 sz = sizeof(vol);
    AudioObjectPropertyAddress vAddr = {
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(dev, &vAddr, 0, NULL, &sz, &vol) == noErr) {
        _systemVolume = TPClampf(vol, 0.0f, 1.0f);
    }

    UInt32 muted = 0;
    sz = sizeof(muted);
    AudioObjectPropertyAddress mAddr = {
        kAudioDevicePropertyMute,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(dev, &mAddr, 0, NULL, &sz, &muted) == noErr) {
        _systemMuted = (muted != 0);
    }
}

- (void)setSystemVolume:(float)vol {
    float clamped = TPClampf(vol, 0.0f, 1.0f);
    AudioDeviceID dev = TPDefaultOutputDevice();
    if (dev == kAudioObjectUnknown) return;

    Float32 v = clamped;
    AudioObjectPropertyAddress vAddr = {
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectSetPropertyData(dev, &vAddr, 0, NULL, sizeof(v), &v) == noErr) {
        _systemVolume = clamped;
        if (clamped > 0.01f && _systemMuted) {
            UInt32 unmute = 0;
            AudioObjectPropertyAddress mAddr = {
                kAudioDevicePropertyMute,
                kAudioObjectPropertyScopeOutput,
                kAudioObjectPropertyElementMain
            };
            AudioObjectSetPropertyData(dev, &mAddr, 0, NULL, sizeof(unmute), &unmute);
            _systemMuted = NO;
        }
    }
}

- (void)stepSystemVolume:(float)delta {
    [self setSystemVolume:_systemVolume + delta];
}

- (void)toggleSystemMute {
    AudioDeviceID dev = TPDefaultOutputDevice();
    if (dev == kAudioObjectUnknown) return;

    UInt32 nextMute = _systemMuted ? 0 : 1;
    AudioObjectPropertyAddress mAddr = {
        kAudioDevicePropertyMute,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectSetPropertyData(dev, &mAddr, 0, NULL, sizeof(nextMute), &nextMute) == noErr) {
        _systemMuted = (nextMute != 0);
    }
}

#pragma mark - Now Playing & Media Controls

- (void)onSpotifyChanged:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    if (!info) return;
    _nowPlayingApp = @"Spotify";
    _nowPlayingTrack = info[@"Name"] ?: @"";
    _nowPlayingArtist = info[@"Artist"] ?: @"";
    NSString *st = info[@"Player State"] ?: @"";
    _nowPlayingIsPlaying = [st isEqualToString:@"Playing"];
}

- (void)onMusicChanged:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    if (!info) return;
    _nowPlayingApp = @"Music";
    _nowPlayingTrack = info[@"Name"] ?: @"";
    _nowPlayingArtist = info[@"Artist"] ?: @"";
    NSString *st = info[@"Player State"] ?: @"";
    _nowPlayingIsPlaying = [st isEqualToString:@"Playing"];
}

- (void)runMediaScriptCommand:(NSString *)cmd {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *targetApp = nil;
        if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"] count] > 0) {
            targetApp = @"Spotify";
        } else if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Music"] count] > 0) {
            targetApp = @"Music";
        }
        if (!targetApp) return;

        NSString *script = [NSString stringWithFormat:@"tell application \"%@\" to %@", targetApp, cmd];
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
        task.arguments = @[ @"-e", script ];
        [task launchAndReturnError:nil];
    });
}

- (void)mediaPlayPause {
    _nowPlayingIsPlaying = !_nowPlayingIsPlaying;
    [self runMediaScriptCommand:@"playpause"];
}

- (void)mediaNext {
    [self runMediaScriptCommand:@"next track"];
}

- (void)mediaPrevious {
    [self runMediaScriptCommand:@"previous track"];
}

#pragma mark - Handy Utilities (Keep Awake, Screenshot, Lock, App Launch)

- (void)toggleKeepAwake {
    [self setKeepAwake:!_keepAwakeActive];
}

- (void)setKeepAwake:(BOOL)enabled {
    if (enabled == _keepAwakeActive) return;
    if (enabled) {
        IOReturn r = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionLevelOn,
            CFSTR("TouchPulse Keep Awake"),
            &_sleepAssertionID
        );
        if (r == kIOReturnSuccess) {
            _hasAssertion = YES;
            _keepAwakeActive = YES;
        }
    } else {
        if (_hasAssertion) {
            IOPMAssertionRelease(_sleepAssertionID);
            _hasAssertion = NO;
        }
        _keepAwakeActive = NO;
    }
}

- (void)takeClipboardScreenshot {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
        task.arguments = @[ @"-i", @"-c" ];
        [task launchAndReturnError:nil];
    });
}

- (void)lockScreenNow {
    void *h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY);
    if (h) {
        void (*lockFn)(void) = (void (*)(void))dlsym(h, "SACLockScreenImmediate");
        if (lockFn) {
            lockFn();
            return;
        }
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pmset"];
        task.arguments = @[ @"displaysleepnow" ];
        [task launchAndReturnError:nil];
    });
}

- (void)launchAppWithBundleID:(NSString *)bundleID fallbackPath:(NSString *)path {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSURL *url = bundleID ? [ws URLForApplicationWithBundleIdentifier:bundleID] : nil;
    if (!url && path) {
        url = [NSURL fileURLWithPath:path];
    }
    if (!url) return;
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.activates = YES;
    [ws openApplicationAtURL:url configuration:cfg completionHandler:nil];
}

#pragma mark - Copy Helpers

- (void)copyCPUHistory:(float *)outBuffer count:(int)count {
    int n = MIN(count, TP_CPU_HISTORY_COUNT);
    for (int i = 0; i < n; i++) {
        int idx = (_cpuHistPos - n + i + TP_CPU_HISTORY_COUNT) % TP_CPU_HISTORY_COUNT;
        outBuffer[i] = _cpuHistory[idx];
    }
}

- (void)copyPerCoreCPU:(float *)outCores maxCount:(int)maxCount {
    int n = MIN(_cpuCoreCount, maxCount);
    if (n > 0) {
        memcpy(outCores, _perCoreUsage, n * sizeof(float));
    }
}

- (NSString *)formattedRate:(double)bytesPerSec {
    if (bytesPerSec >= 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1fM", bytesPerSec / (1024.0 * 1024.0)];
    } else if (bytesPerSec >= 1024.0) {
        return [NSString stringWithFormat:@"%.0fK", bytesPerSec / 1024.0];
    }
    return [NSString stringWithFormat:@"%.0fB", bytesPerSec];
}

@end

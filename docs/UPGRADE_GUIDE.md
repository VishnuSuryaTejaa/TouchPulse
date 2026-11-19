# 🔧 TouchPulse Developer & Future Upgrade Guide

This guide explains how **TouchPulse** works internally and provides concrete, copy-pasteable blueprints for adding new modes, adding new Power HUD widgets, and implementing the major future architectural upgrades.

---

## 1. How TouchPulse Works Under the Hood

### Unified Dual-Surface Rendering
Both the **real hardware Touch Bar** (`TPTouchBarController`) and the **on-screen interactive Mirror** (`TPControlCenterWindow`) instantiate the same `TPTouchBarCanvasView` class.
- On the real Touch Bar, `TPTouchBarCanvasView` receives direct multi-touch events via `touchesBeganWithEvent:` / `touchesMovedWithEvent:` / `touchesEndedWithEvent:` (`NSTouchTypeMaskDirect`).
- On screen, `TPTouchBarCanvasView` converts `mouseDown:` / `mouseDragged:` / `mouseUp:` into the exact same normalized coordinate pipeline.
- Both surfaces register with `[TPEngine shared]` and render from the exact same `renderInContext:size:` call.

### Always-On System Modal Touch Bar (`DFRFoundation`)
`TPTouchBarController.m` dynamically resolves Apple's private Touch Bar system modal symbols via `dlopen` and `objc_msgSend`:
- `+[NSTouchBarItem addSystemTrayItem:]` + `DFRElementSetControlStripPresenceForIdentifier()` — installs the quick-toggle glyph into the macOS Control Strip.
- `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`:
  - `placement = 0`: App Region (keeps macOS Control Strip visible on the right).
  - `placement = 1`: Full-Width Cinema Mode (edge-to-edge across the Touch Bar).
- Automatically observes `NSWorkspaceDidWakeNotification` & `NSWorkspaceScreensDidWakeNotification` to re-present the Touch Bar after sleep/wake.

### Real-Time Audio DSP (`TPAudioEngine`)
- Uses `AVAudioEngine` + `AVAudioSourceNode` running pure C synthesis on the CoreAudio render thread protected by `os_unfair_lock`.
- Lazy startup + silent-frame idle bypass: consumes **0% audio CPU** until a note/SFX triggers and returns `*isSilence = YES` once voices + stereo ping-pong delay tails decay.
- Separate input `AVAudioEngine` runs a 512-sample Hann-windowed `Accelerate` `vDSP_fft_zrip` into 36 logarithmic frequency bands for **Spectrum Pulse**.

---

## 2. How to Add a Brand-New Mode (#13+)

Adding a new visual, game, or instrument takes ~5 clean touches:

1. **Declare the enum in `src/TPCommon.h`:**
   ```objc
   TPModeMyNewMode = 12,
   TPModeCount = 13
   ```
2. **Add display metadata in `src/TPTheme.m`:**
   Add cases to `TPModeName()`, `TPModeSubtitle()`, and `TPModeSymbol()`.
3. **Add flat C simulation state to `src/TPEngine.h`:**
   Add your struct/arrays inside the `@public` ivar block of `TPEngine`, and declare `stepMyNewMode:`, `renderMyNewMode:rect:`, and touch callbacks in a category (`VisualModes`, `ChaosModes`, `ArcadeModes`, or a new `TPModesCustom.m`).
4. **Hook into `src/TPEngine.m`:**
   - Call your `step...` inside `tick`
   - Call your `touch...` inside `handleTouchBeganID:` / `MovedID:` / `EndedID:`
   - Call your `render...` inside `renderInContext:size:`
5. **Update `src/TPControlCenterWindow.m` (and `build.sh` if adding a new `.m` file):**
   The Control Center grid loops `0 .. TPModeCount - 1` automatically — just adjust window height/rows if going past 12 cards, then run `./build.sh`!

---

## 3. How to Add a New Widget to the Slidable Power HUD Deck

Because `src/TPModesTools.m` renders into a single translated virtual horizontal coordinate space (`vx`), adding a new widget never breaks layout or clips existing widgets!

1. **Add a `CGRect _hitMyWidget;` ivar** to `TPEngine.h` (if interactive).
2. **Draw the card inside `renderTools:rect:` in `src/TPModesTools.m`:**
   ```objc
   CGRect myR = CGRectMake(vx, cardY, 130.0, cardH);
   _hitMyWidget = myR;
   TPDrawDeckCard(ctx, myR, TPThemeColor(_theme, 0.5f, 1.0f), NO);
   TPDrawText(ctx, @"MY WIDGET", CGPointMake(vx + 10.0, cardY + 6.5),
              9.5, NSFontWeightBold, [NSColor whiteColor], YES);
   vx += 130.0 + gap;
   ```
   `_hudMaxScroll` automatically recalculates from final `vx - r.size.width`!
3. **Handle tap inside `touchToolsEndedID:point:rect:`:**
   ```objc
   if (CGRectContainsPoint(_hitMyWidget, vpt)) {
       // Your action here!
       [[TPAudioEngine shared] playSFX:TPSFXClick pan:0.0f pitchScale:1.2f];
       [self showToast:@"MY ACTION" subtitle:@"Triggered!"];
       return;
   }
   ```

---

## 4. Blueprints for Major Future Upgrades

### Upgrade A: Zero-Mic Direct System Audio Visualizer (macOS 14.2+ CoreAudio Process Tap)
Currently, **Spectrum Pulse** uses the microphone input (`AVAudioEngine.inputNode`) for live FFT. To capture macOS speaker audio directly without microphone noise:
- Use `CATapDescription` (`initStereoGlobalTapButExcludeProcesses:@[]`) + `AudioHardwareCreateProcessTap()` to create an aggregate CoreAudio tap device.
- Feed the tap's IOProc float buffer directly into the existing `processMicBuffer:` `vDSP_fft_zrip` pipeline in `TPAudioEngine.m`.
- Add `NSAudioCaptureUsageDescription` to `Info.plist` inside `build.sh`.

### Upgrade B: Metal GPU Shader Backend (`CAMetalLayer`)
For heavy GPU effects (Navier-Stokes 2D fluid smoke, raymarched 3D tunnels, fractal zoomers, neon bloom post-processing):
- Add an optional `TPTouchBarMetalView` backed by `CAMetalLayer` (`pixelFormat = MTLPixelFormatBGRA8Unorm`).
- Pass a compact uniform struct (`time`, `resolution`, `themeID`, `mouseNormX`, `touchPositions[10]`, `spectrumBands[36]`) into `.metal` fragment shaders compiled during `build.sh` via `xcrun metal` & `xcrun metallib`.
- Keep CoreGraphics for crisp vector/text modes (`Power HUD`, `Matrix`, `Synth`) and dispatch shader modes to Metal!

### Upgrade C: Persistent Settings & JSON-Configurable Power HUD
- Persist `mode`, `theme`, `synthScale`, `speedScale`, `fullWidthMode`, `alwaysOnActive`, `showModePill`, `mouseReactive`, and `soundEnabled` via `NSUserDefaults` inside setters in `TPEngine.m` and `TPTouchBarController.m`.
- Load an optional JSON layout from `~/Library/Application Support/TouchPulse/hud.json` allowing users to reorder Power HUD cards, hide unused ones, or define custom shell-command buttons:
  ```json
  {
    "customButtons": [
      { "label": "🚀 Deploy", "command": "/usr/local/bin/my-script.sh", "color": "#00F5FF" },
      { "label": "🎧 AirPods", "command": "blueutil --connect AA-BB-CC-DD-EE-FF", "color": "#FF24A8" }
    ]
  }
  ```

### Upgrade D: Launch at Login (`SMAppService`)
On macOS 13+, link `-framework ServiceManagement` and expose a single checkbox in `TPControlCenterWindow.m`:
```objc
#import <ServiceManagement/ServiceManagement.h>
SMAppService *svc = [SMAppService mainAppService];
if (enable) [svc registerAndReturnError:&err];
else [svc unregisterAndReturnError:&err];
```

### Upgrade E: Universal Binary (`x86_64` + `arm64`)
To distribute one `TouchPulse.app` supporting both Intel MacBook Pros and Apple Silicon (M1/M2 13-inch Touch Bar MacBook Pros), update `build.sh` to compile both slices and combine them with `lipo`:
```bash
clang -arch x86_64 ... -o "$BUILD_TMP/TouchPulse_x86"
clang -arch arm64  ... -o "$BUILD_TMP/TouchPulse_arm"
lipo -create "$BUILD_TMP/TouchPulse_x86" "$BUILD_TMP/TouchPulse_arm" -output "$MACOS/TouchPulse"
```

### Upgrade F: Global Hotkeys & Keystroke Shockwave Mode
- **Global Hotkeys**: Use `RegisterEventHotKey` (Carbon framework) to let users switch modes or toggle Full-Width Cinema mode from any foreground application.
- **Keystroke Shockwave**: Add an opt-in Accessibility-gated `CGEventTapCreate` listener (`kCGEventKeyDown`) that maps physical key codes to their X-position right underneath the Touch Bar (`Esc..Delete` mapped `0.0..1.0`) so every key you type launches sparks or wave ripples directly above your finger!

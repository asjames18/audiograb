# AudioGrab

A small native macOS app (Swift + SwiftUI) that records your Mac's system audio to files.
It uses ScreenCaptureKit, so no BlackHole or other virtual audio driver is needed.

- Record all system audio, or just one app
- Big Record/Stop button, live level meter and elapsed time
- WAV (48 kHz, 16-bit stereo) or M4A (AAC 256 kbps)
- Name each recording before you start (default `Recording YYYY-MM-DD HH-mm-ss`; `/`, `:` and other illegal characters are removed)
- Output folder is remembered between launches (default `~/Music/AudioGrab`)
- Auto-split: start a new file after a stretch of silence (`<name> 01`, `<name> 02`, …), with adjustable threshold and length
- Trim silence at the start and end of each file
- List of recordings with play, show in Finder, rename and move to Trash
- Menu bar item with Start/Stop, plus a global shortcut: **⌥⌘R**
- No network access, no analytics. Nothing leaves your Mac.

Requires macOS 14 or later (built and tested for macOS 26 Tahoe). Runs natively on Intel and Apple silicon.

## Install the prebuilt app

1. Unzip `AudioGrab.zip` and drag **AudioGrab.app** into **Applications**.
2. The app is ad-hoc signed (no paid Apple Developer account), so the first time,
   right-click (or Control-click) AudioGrab in Applications and choose **Open**, then **Open** again.
   If macOS still blocks it, go to System Settings › Privacy & Security and click **Open Anyway**.
3. Press Record. macOS asks for **Screen & System Audio Recording** permission. Allow it
   (or use the **Open System Settings** button in the app, turn AudioGrab on, then quit and reopen AudioGrab).

macOS ties the permission to the app's signature. An ad-hoc signed app gets a new signature on every
rebuild, so after installing a new build you may need to turn AudioGrab off and on again in
System Settings › Privacy & Security › Screen & System Audio Recording.

## Build from source

Needs Xcode 15 or later (tested with Xcode 26.5).

```sh
git clone https://github.com/asjames18/audiograb.git
cd audiograb
scripts/build.sh            # runs unit tests, builds universal Release, ad-hoc signs, zips
open build/AudioGrab.app
```

Or by hand:

```sh
# unit tests
xcodebuild -project AudioGrab.xcodeproj -scheme AudioGrab -destination "platform=macOS" test

# universal Release build
xcodebuild -project AudioGrab.xcodeproj -scheme AudioGrab -configuration Release \
  -derivedDataPath build/DerivedData ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO build

# ad-hoc sign
cp -R build/DerivedData/Build/Products/Release/AudioGrab.app build/
codesign --force --deep -s - build/AudioGrab.app
codesign --verify --strict build/AudioGrab.app
```

You can also open `AudioGrab.xcodeproj` in Xcode and press Run.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The generated project is committed, so XcodeGen is only needed if you change `project.yml`
(`brew install xcodegen && xcodegen generate`, or `REGENERATE=1 scripts/build.sh`).

## How it works

- `Capture/SystemAudioCapture.swift`: an `SCStream` with `capturesAudio = true` and
  `excludesCurrentProcessAudio = true`. ScreenCaptureKit always needs a display in the filter,
  so video is requested at 2×2 pixels once per second and ignored. For a single app the
  filter is `SCContentFilter(display:including:[app]…)`.
- `Audio/RecordingSession.swift`: receives audio buffers, drives the level meter and auto-split,
  and writes each segment to a temporary file. When a segment ends it's converted to the final
  WAV/M4A (`Audio/RecordingExporter.swift`, using `AVAudioFile`), trimming silence if enabled,
  and the temporary file is deleted. Existing files are never overwritten (`Name (2).wav`).
- `Core/`: pure Swift logic with unit tests: file naming and sanitizing, level and silence
  detection, the auto-split state machine, silence trimming, disk-full detection.
- Global shortcut: Carbon `RegisterEventHotKey`, which needs no Accessibility permission.
- The output folder is stored as a security-scoped bookmark in UserDefaults.
- The app is not sandboxed (the sandbox is optional for a personal, non-App Store app).

## Errors you might see

- **Screen & System Audio Recording is off**: turn AudioGrab on in System Settings, then reopen it.
- **Disk is full**: recording stops when free space drops below 100 MB; what was recorded is saved if possible.
  Recording won't start with less than 200 MB free.
- **Recording was interrupted / stopped**: macOS ended the stream (for example from the screen-recording
  indicator in the menu bar). Audio captured up to that point is saved.
- **App isn't running**: the selected app was closed; open it or pick "All system audio".

## Tests

`AudioGrabTests` covers file naming and sanitizing, silence detection and level math, the auto-split
state machine, trimming, WAV/M4A export formats, and full recording sessions fed with generated audio
(splitting into `Show 01`, `Show 02`, trimming, never overwriting).

## License

MIT. See [LICENSE](LICENSE).

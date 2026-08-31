# Caffeinated

A lightweight macOS menu bar utility that keeps your Mac awake — plus a live system monitor and a frozen-screen capture tool.

No Dock icon. Look for the coffee cup on the right side of the menu bar.

## Install

Grab **Caffeinated.zip** from the [latest GitHub Release](https://github.com/AgarwalAarush/Caffeinated/releases/latest), unzip, and drag **Caffeinated.app** to Applications.

The build is ad-hoc signed: right-click → **Open** the first time. After that, **Check for Updates…** (Settings in the popover, or the Caffeinated menu) opens a software-update window. Settings → Check Automatically looks for newer releases about every 12 hours. You do not need GitHub Actions artifacts.

**The GitHub repo must be public** for in-app updates. The app calls `releases/latest` with no token; a private repo 404s both the API and the zip.

## Features

### Awake

- **One-tap toggle** in the menu bar — flip the iOS-style pill switch to prevent your Mac from dimming the screen or starting the screensaver.
- **Timed sessions** — pick `∞` (until you turn it off) or `15 / 30 / 45` minutes, `1 / 4 / 8 / 12` hours. Remaining time sits next to the cup while a timer is running.
- **Keep going with the lid closed** — stays awake after you close the lid, no external display required. Sleep is fully disabled for that session; mind heat and power. Restored on stop, quit, and the next launch if the app was killed mid-session.
- **Allow Display Sleep** — keep the Mac working while the screen is allowed to dim (`caffeinate -i` instead of `-d`).
- **Open at Login** — registers the app via `SMAppService` so it's there next time you log in.
- **Pause on Battery** — opt-in. When enabled, Caffeinated turns itself off the moment your Mac switches from AC power to battery.
- **Notify When Timer Ends** — opt-in. When a timed session expires naturally, a macOS notification banner lets you know it stopped.
- **Check for Updates…** — a software-update window (not a row in the popover). Pulls `Caffeinated.zip` from GitHub Releases and replaces the app.

### Stats

Live readouts in the popover (sampled only while the Stats tab is open):

- **CPU** and **GPU** utilization
- **Memory** used / total, with a caution/urgent tint under pressure
- **Storage** used / total on the boot volume
- **Battery** percent, charging state, time remaining, **health**, **cycle count**, **power draw**, and battery temperature

### Capture

A frozen-screen screenshot tool (Screen Recording permission, requested on first use):

- **Selection** — drag a region
- **Window** — click a window
- **Screen** — click a display (immediate if you only have one)
- Optional auto-copy to the clipboard, a floating preview with Copy / Save / Done, and a last-capture thumbnail in the tab

The screen is captured *before* the overlay appears, so Caffeinated's own UI is never in the shot.

## How it works

**Awake.** Caffeinated takes out an [`IOPMAssertion`](https://developer.apple.com/documentation/iokit/iopmassertioncreatewithname) while active:

- Display + system: `PreventUserIdleDisplaySleep` (same as `caffeinate -d`)
- System only: `PreventUserIdleSystemSleep` (`caffeinate -i`)
- Closed lid: `PreventSystemSleep` plus the IOPMrootDomain clamshell-sleep disable bit (selector 12). A normal caffeinate assertion does **not** survive closing the lid on Apple Silicon.

The assertion is released automatically if the app exits. The clamshell bit is sticky, so Caffeinated records when it armed it and always restores it on stop, quit, and launch-after-crash.

Power-source transitions are observed via `IOPSNotificationCreateRunLoopSource`. Launch-at-login uses `SMAppService.mainApp`. Notifications use `UserNotifications` with permission requested lazily.

**Stats.** CPU comes from Mach `host_statistics`; memory from `host_statistics64`; GPU from IOAccelerator `PerformanceStatistics`; battery/power from `IOPSCopyPowerSourcesInfo` plus the `AppleSmartBattery` IORegistry entry; disk from Foundation volume resource values. Nothing shells out to `powermetrics`.

**Capture.** [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) takes a still of each display, then an overlay lets you crop. Saving uses `NSSavePanel`.

**Updates.** **Check for Updates…** lives under Settings (and the Caffeinated app menu). It opens a small software-update window, then calls GitHub’s `releases/latest` API, downloads `Caffeinated.zip`, swaps the running `.app` (with a backup restore if `ditto` fails), clears quarantine (`xattr -cr`), and relaunches via a detached `nohup` helper. Sparkle is skipped because CI/release builds are ad-hoc signed. The repo has to be public — private GitHub releases are invisible to an unauthenticated `URLSession`.

The app is not App-Sandboxed: closed-lid mode has to talk to `IOPMrootDomain`. Hardened Runtime stays on.

## Project layout

```
Caffeinated/
├── CaffeinatedApp.swift       MenuBarExtra scene, remaining-time label, terminate cleanup
├── PopoverRoot.swift          Awake / Stats / Capture tabs
├── ContentView.swift          Awake tab: toggle, duration, closed lid, Settings, About, Quit
├── StatsView.swift            Live meters + battery
├── CaptureView.swift          Capture tab
├── CaffeinateManager.swift    IOPMAssertion lifecycle, duration timer, prefs, clamshell policy
├── ClamshellSleep.swift       IOPMrootDomain lid-close sleep flag
├── PowerSourceMonitor.swift   AC↔Battery transition observer
├── SystemMonitor.swift        CPU / GPU / RAM / disk / battery sampler
├── ScreenshotController.swift Frozen overlay, crop, preview, clipboard, save
├── LaunchAtLogin.swift        SMAppService wrapper
├── UpdateChecker.swift        GitHub Releases checker / in-place installer
├── UpdatePrompt.swift         Software-update window
└── Assets.xcassets/
    └── AppIcon.appiconset/    Custom coffee-mug icon (16–1024px)
```

## Building

Requires Xcode 26+ targeting macOS 26.4 (Swift 5, MainActor isolation by default).

```bash
git clone https://github.com/AgarwalAarush/Caffeinated.git
cd Caffeinated
xcodebuild -project Caffeinated.xcodeproj -scheme Caffeinated -configuration Release build
```

Or open `Caffeinated.xcodeproj` in Xcode and hit Cmd-R.

Push a `v*` tag to publish a GitHub Release (`Caffeinated.zip`) via `.github/workflows/release.yml`. PR builds still upload an Actions artifact for testing; that is not the update feed.

The app is configured with `LSUIElement = true`, so it has no Dock icon — look for the coffee cup in the right side of your menu bar after launch.

First capture will prompt for **Screen Recording** in System Settings. Closed-lid mode needs no extra prompt.

If a closed-lid session is force-killed and the Mac will not sleep, reopen Caffeinated (it restores the flag on launch) or reboot.

## Settings

Preferences live behind the **Settings** disclosure on the Awake tab and are persisted to `UserDefaults`:

| Setting | Default | Behavior |
|---|---|---|
| Open at Login | off | Registers `SMAppService.mainApp` |
| Pause on Battery | off | Auto-disables Caffeinated on AC → Battery transition |
| Allow Display Sleep | off | Prevents idle *system* sleep but lets the display dim |
| Notify When Timer Ends | off | Posts a `UNUserNotification` when a timed session naturally expires |
| Check Automatically | on | Looks for a newer GitHub Release about every 12 hours |
| Copy to Clipboard | on | Capture tab: copy each shot automatically |

Closed-lid is a session option on the Awake tab, not buried in Settings.

## License

MIT.

This project is original code. It is **not** derived from [Vorssaint](https://github.com/vorssaintapp/vorssaint-utils) (GPL-3.0).

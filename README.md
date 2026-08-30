# Caffeinated

[![Build](https://github.com/AgarwalAarush/Caffeinated/actions/workflows/build.yml/badge.svg)](https://github.com/AgarwalAarush/Caffeinated/actions/workflows/build.yml)

A lightweight macOS menu bar utility that keeps your Mac awake — plus a live system monitor and a frozen-screen capture tool.

No Dock icon. Look for the coffee cup on the right side of the menu bar.

## Install

Every push to `main` (and every pull request) builds a Release `Caffeinated.app` on GitHub Actions:

1. Open the latest green [**Build**](https://github.com/AgarwalAarush/Caffeinated/actions/workflows/build.yml) run.
2. Download the **Caffeinated** artifact (`Caffeinated.zip`).
3. Unzip and drag `Caffeinated.app` into `/Applications`.

The CI binary is ad-hoc signed (no Developer ID). First launch: right-click → **Open**. Open at Login works most reliably once the app lives in `/Applications`.

## Features

### Awake

- **One-tap toggle** in the menu bar — flip the iOS-style pill switch to prevent your Mac from dimming the screen or starting the screensaver. The cup fills while a session is running.
- **Timed sessions** — pick `∞` (until you turn it off) or `15 / 30 / 45` minutes, `1 / 4 / 8 / 12` hours. Remaining time sits next to the cup while a timer is running. Choosing a duration while the session is off starts it.
- **Keep going with the lid closed** — stays awake after you close the lid, no external display required. Sleep is fully disabled for that session; mind heat and power. Restored on stop, quit, and the next launch if the app was killed mid-session. The toggle itself is remembered across launches.
- **Allow Display Sleep** — keep the Mac working while the screen is allowed to dim (`caffeinate -i` instead of `-d`).
- **Open at Login** — registers the app via `SMAppService` so it's there next time you log in.
- **Pause on Battery** — opt-in. When enabled, Caffeinated turns itself off the moment your Mac switches from AC power to battery.
- **Notify When Timer Ends** — opt-in. When a timed session expires naturally, a macOS notification banner lets you know it stopped.

### Stats

Live readouts in the popover (sampled only while the Stats tab is open):

- **CPU** and **GPU** utilization
- **Memory** used / total, with a caution/urgent tint under pressure
- **Storage** used / total on the boot volume
- **Battery** percent, charging state, time remaining, **health**, **cycle count**, **power draw**, and battery temperature

Desktops without a battery show “No battery”. GPU reads `—` if IOAccelerator does not report utilization.

### Capture

A frozen-screen screenshot tool (Screen Recording permission, requested on first use):

- **Selection** — drag a region
- **Window** — click a window
- **Screen** — click a display (immediate if you only have one)
- Optional auto-copy to the clipboard, a floating preview with Copy / Save / Done, and a last-capture thumbnail in the tab
- **Esc** cancels; **Return** confirms a selection

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

The app is not App-Sandboxed: closed-lid mode has to talk to `IOPMrootDomain`. Hardened Runtime stays on.

## Project layout

```
.
├── Caffeinated/
│   ├── CaffeinatedApp.swift       MenuBarExtra scene, remaining-time label, terminate cleanup
│   ├── PopoverRoot.swift          Awake / Stats / Capture tabs
│   ├── ContentView.swift          Awake tab: toggle, duration, closed lid, Settings, About, Quit
│   ├── StatsView.swift            Live meters + battery
│   ├── CaptureView.swift          Capture tab
│   ├── CaffeinateManager.swift    IOPMAssertion lifecycle, duration timer, prefs, clamshell policy
│   ├── ClamshellSleep.swift       IOPMrootDomain lid-close sleep flag
│   ├── PowerSourceMonitor.swift   AC↔Battery transition observer
│   ├── SystemMonitor.swift        CPU / GPU / RAM / disk / battery sampler
│   ├── ScreenshotController.swift Frozen overlay, crop, preview, clipboard, save
│   ├── LaunchAtLogin.swift        SMAppService wrapper
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/    Custom coffee-mug icon (16–1024px)
├── Caffeinated.xcodeproj/
├── .github/workflows/build.yml    Release build on macOS 26 / Xcode 26.5
├── LICENSE
└── README.md
```

## Building

Requires Xcode 26.5+ targeting macOS 26.4 (Swift 5, MainActor isolation by default). The Xcode project was created with Xcode 26.5; CI uses that same toolchain.

```bash
git clone https://github.com/AgarwalAarush/Caffeinated.git
cd Caffeinated
xcodebuild -project Caffeinated.xcodeproj -scheme Caffeinated -configuration Release build
```

Or open `Caffeinated.xcodeproj` in Xcode and hit Cmd-R.

The app is configured with `LSUIElement = true`, so it has no Dock icon — look for the coffee cup in the right side of your menu bar after launch.

First capture will prompt for **Screen Recording** in System Settings. Closed-lid mode needs no extra prompt.

If a closed-lid session is force-killed and the Mac will not sleep, reopen Caffeinated (it restores the flag on launch) or reboot.

### CI

`.github/workflows/build.yml` runs on `macos-26` with Xcode 26.5. It ad-hoc signs (`CODE_SIGN_IDENTITY="-"`), zips `Caffeinated.app`, and uploads the **Caffeinated** artifact.

## Settings

Hover **Settings** on the Awake tab to expand it (click is a no-op). Preferences persist to `UserDefaults`:

| Setting | Default | Behavior |
|---|---|---|
| Open at Login | off | Registers `SMAppService.mainApp` |
| Pause on Battery | off | Auto-disables Caffeinated on AC → Battery transition |
| Allow Display Sleep | off | Prevents idle *system* sleep but lets the display dim |
| Notify When Timer Ends | off | Posts a `UNUserNotification` when a timed session naturally expires |

Closed-lid is a session option on the Awake tab, not buried in Settings.

On the **Capture** tab, **Copy to Clipboard** defaults to on and copies each shot automatically.

## License

MIT. See [LICENSE](LICENSE).

This project is original code. It is **not** derived from [Vorssaint](https://github.com/vorssaintapp/vorssaint-utils) (GPL-3.0).

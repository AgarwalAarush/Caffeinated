# Caffeinated

A lightweight macOS menu bar utility that keeps your Mac awake.

No Dock icon. No main window. Just a coffee-cup glyph in the menu bar with a focused popover for picking how long to stay caffeinated.

## Features

- **One-tap toggle** in the menu bar — flip the iOS-style pill switch to prevent your Mac from dimming the screen or starting the screensaver.
- **Timed sessions** — pick `∞` (until you turn it off) or `15 / 30 / 45` minutes, `1 / 4 / 8 / 12` hours.
- **Open at Login** — registers the app via `SMAppService` so it's there next time you log in.
- **Pause on Battery** — opt-in. When enabled, Caffeinated automatically turns itself off the moment your Mac switches from AC power to battery (so you don't drain your laptop overnight because you forgot to flip it off).
- **Notify When Timer Ends** — opt-in. When a timed session expires naturally, a macOS notification banner lets you know it stopped.
- **Custom app icon + menu-bar glyph** that swaps between filled and outlined to reflect active state.

## How it works

Caffeinated takes out an [`IOPMAssertion`](https://developer.apple.com/documentation/iokit/iopmassertioncreatewithname) of type `kIOPMAssertionTypePreventUserIdleDisplaySleep` while active. This is the same primitive that the built-in `caffeinate -d` command uses, just held directly in-process — no subprocess, plays nicely with the App Sandbox, and the assertion is released automatically if the app exits.

Power-source transitions are observed via `IOPSNotificationCreateRunLoopSource` (kernel push, no polling). Launch-at-login uses `SMAppService.mainApp` (the modern API since macOS 13). Notifications use `UserNotifications.framework` with permission requested lazily — only when you opt in to the notify-on-timer-end setting.

## Project layout

```
Caffeinated/
├── CaffeinatedApp.swift       MenuBarExtra scene + UNUserNotificationCenter delegate
├── ContentView.swift          Popover UI: header toggle, duration pills, Settings, About, Quit
├── CaffeinateManager.swift    IOPMAssertion lifecycle, duration timer, prefs
├── PowerSourceMonitor.swift   AC↔Battery transition observer
├── LaunchAtLogin.swift        SMAppService wrapper
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

The app is configured with `LSUIElement = true`, so it has no Dock icon — look for the coffee cup in the right side of your menu bar after launch.

## Settings

All preferences live behind the **Settings** disclosure in the popover and are persisted to `UserDefaults`:

| Setting | Default | Behavior |
|---|---|---|
| Open at Login | off | Registers `SMAppService.mainApp` |
| Pause on Battery | off | Auto-disables Caffeinated on AC → Battery transition |
| Notify When Timer Ends | off | Posts a `UNUserNotification` when a timed session naturally expires |

## License

MIT.

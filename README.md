# Batteries 🔋

A macOS menu bar app that shows battery levels for your Mac and all your
connected devices — iPhone, iPad, AirPods, Bluetooth headphones, Magic
Keyboard/Mouse/Trackpad — and notifies you when any of them run low.

## Features

- **Battery levels, anywhere** — click the battery icon in the menu bar to see
  your Mac's battery (with power source and charging state, like the native
  battery menu) plus every connected device that reports a battery level.
- **iPhone, iPad, and whatnot** — Apple accessories and any Bluetooth
  headphones appear automatically while connected. iPhones/iPads appear over
  USB or Wi-Fi via [libimobiledevice](https://libimobiledevice.org) (see below).
- **Get notified when you need to recharge** — when any device drops below the
  threshold (default 20%, configurable to 10/15/20/30%), you get a macOS
  notification. Each device alerts once per discharge cycle, and re-arms when
  it recovers or starts charging.
- Extras: show/hide percentage in the menu bar, Launch at Login, AirPods
  per-component detail (Left/Right/Case) as a tooltip, auto-refresh every
  60 seconds plus refresh on menu open.

## Build & run

```bash
./build.sh
open build/Batteries.app
```

Requires macOS 13+ and the Xcode command line tools. The script builds with
SwiftPM, packages `Batteries.app`, and ad-hoc signs it (needed for
notifications and Launch at Login).

On first launch, allow notifications when macOS asks. Enable **Preferences →
Launch at Login** from the app's menu to keep it running.

## iPhone / iPad batteries

macOS doesn't expose iOS battery levels to third-party apps directly, so the
app uses libimobiledevice, the same open-source stack most battery utilities
use:

```bash
brew install libimobiledevice
```

Then:

1. Connect your iPhone/iPad via USB once and tap **Trust**.
2. For Wi-Fi: in Finder, select the device and enable
   **"Show this iPhone when on Wi-Fi"**.
3. As long as it's on the same network, its battery shows up in the menu.

## How it works

| Source | Mechanism |
|---|---|
| Mac battery | IOKit power sources (`IOPSCopyPowerSourcesInfo`) |
| Bluetooth devices | `system_profiler SPBluetoothDataType -json` |
| iPhone / iPad | `idevice_id` + `ideviceinfo` (libimobiledevice) |
| Notifications | `UserNotifications` framework |
| Launch at Login | `SMAppService` |

## Notes

- A Notification Center (Today View) widget and Touch Bar support would need
  a full Xcode project with a WidgetKit extension and a paid developer
  signing identity; the menu bar covers the same information in one click.
- Bluetooth devices only appear if they report a battery level to macOS
  (check System Settings → Bluetooth — if a level shows there, it shows here).

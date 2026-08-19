## 1.4

- AirPods pop-up: open your AirPods case next to the Mac and an iPhone-style card drops in showing the earbud and case battery — with the right product image for your model — plus a one-click Connect. On by default; grant Bluetooth when asked. You can turn it off in App Settings → "AirPods Pop-up When Case Opens".
- Show AirPods battery right in the menu, live, the moment the case opens nearby — even before they're connected. On by default; App Settings → "Show AirPods Battery in Menu".
- Battery percentage for Bluetooth accessories macOS doesn't otherwise report — mice, keyboards, and headphones with the standard Bluetooth battery service (e.g. an MX Master) now show their level instead of "—", read directly over Bluetooth.
- Pause a battery-hungry app until you're back on power: each app under "Apps Using Significant Energy" now has a "Pause Until Plugged In" action that freezes it so it stops draining the battery, then automatically resumes it when you plug in.
- Silence energy notifications per app: each energy-intensive app has a "Notify About This App" toggle, so a pro tool you knowingly run hot won't keep nagging you while you still hear about unexpected new ones.
- Low-battery and full-charge notifications are now actionable — "Snooze 1h" and "Mute This Device" right from the notification.
- Menu bar icon fixes: the fill now always matches the true charge level (it previously looked full while charging), and plugging or unplugging the charger updates the icon instantly instead of after a delay.
- App Settings is now its own window (Cmd+,) instead of a submenu, laid out as a proper form so it's easy to scan.
- New "Hide devices without a battery level" setting, for an iPad or Watch that's paired but never reports a percent.
- Fresh app icon.

## 1.3

- Battery percentage for Bluetooth accessories that macOS doesn't otherwise report — mice, keyboards, and headphones that expose the standard Bluetooth battery service (e.g. an MX Master) now show their level instead of "—", read directly over Bluetooth.
- Connect or disconnect your Bluetooth devices (AirPods, headphones, Magic mouse/keyboard/trackpad) right from the menu — a new "Connect / Disconnect" submenu with a checkmark for what's connected. macOS asks for Bluetooth permission the first time.

## 1.2

- Connect or disconnect your Bluetooth devices right from the menu (a new "Connect / Disconnect" submenu). Superseded by 1.3, which ships this plus BLE battery readings.

## 1.1

- Quick Low Power Mode toggle right in the menu (authorizes with your Mac password, since macOS requires admin rights to change it).
- New "Apps Using Significant Energy" section that lists the applications currently draining the most battery — helper processes are rolled up to their app, so you see "Chrome", not a dozen renderers. Click one to bring it to the front. Optional notifications when an app becomes a heavy drain.
- Cleaner menu typography: a clearer title / device / detail size hierarchy.

## 1.0.0

First QStore release. Menu bar battery levels for your Mac, iPhone, iPad, Apple Watch, AirPods, and other Bluetooth accessories — including devices connected only via Bluetooth Continuity, no cable required. Low-battery and full-charge notifications with per-device muting, a 24-hour history graph, a proportional menu bar icon that turns red when critical, and automatic updates.

## 1.4

- AirPods pop-up: open your AirPods case next to the Mac and an iPhone-style card drops down showing the earbud and case battery, with a one-click Connect. Turn it on in App Settings → "AirPods Pop-up When Case Opens" (it uses always-on Bluetooth scanning, so it's off by default).

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

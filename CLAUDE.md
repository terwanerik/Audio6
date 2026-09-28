# Audio6

Native (Apple Silicon) macOS menu bar app that replaces the Intel-only
"Traktor Audio 6 Control Panel" (needs Rosetta). It controls the input source
(phono/line) and thru mode of a Native Instruments Traktor Audio 6, both live
and as the power-on (startup) config.

## USB protocol (reverse engineered, confirmed working)

Vendor control requests on endpoint 0, device recipient. Vendor ID 0x17CC.

| | bmRequestType | bRequest | wValue | wIndex | wLength |
|---|---|---|---|---|---|
| write | 0x40 | REQ | VALUE | CHANNEL | 0 |
| read  | 0xC0 | REQ | 0 | CHANNEL | 1 |

- REQ 1 = thru mode, REQ 2 = input source (phono/line). VALUE 0 or 1.
- CHANNEL: A = 3, B = 5.
- Startup config: same requests with wIndex + 0x100 (0x103 / 0x105), followed by
  bRequest 0x10 (wValue 0, wIndex 0) to store it. Confirmed to persist.
- Which input value means Phono vs Line is NOT confirmed yet
  (currently assumed 0 = Line, 1 = Phono, see `InputSource` in Device.swift).
- The original app polls both settings for both channels about every 0.8 s.

`ta6.py` is a working pyusb CLI for the same protocol (reference / testing).

## Project layout

- `Package.swift` - SwiftPM, macOS 13+. Targets: `TA6USB` (C) and `Audio6` (Swift).
- `Sources/TA6USB/ta6usb.c` - IOKit / IOUSBLib device lookup + DeviceRequest.
  Lists all USB devices, target selectable by vid/pid (default: any 0x17CC,
  preferring a name containing "Audio 6"). No device open/seize needed.
- `Sources/Audio6/Device.swift` - protocol constants, `USB` helpers,
  `DeviceModel` (ObservableObject, serial USB queue, 2 s polling, device
  selection persisted in UserDefaults key "device").
- `Sources/Audio6/Audio6App.swift` - NSStatusItem + custom borderless,
  shadowless `MenuPanel` attached under the menu bar; SwiftUI `ContentView`
  with Live / Startup tabs, per-channel input picker + thru toggle, device picker.
- `Resources/Icon.icon` - Icon Composer app icon (compiled by actool, Xcode 26).
- `VERSION` - app marketing version (CFBundleShortVersionString).
- `build-app.sh` - builds `build/Audio6.app` (Info.plist with LSUIElement,
  icon, ad-hoc codesign). Version from `VERSION`; `BUILD_NUMBER` env sets
  CFBundleVersion.
- `.github/workflows/build.yml` - builds on every push/PR (macos-26 runner).
- `.github/workflows/release.yml` - on `v*` tag push: fails unless the tag
  matches `VERSION`, builds, creates a GitHub release with `Audio6.zip` and notes from the
  commits since the previous tag.

## Build / run

    ./build-app.sh && open build/Audio6.app
    # or for quick iteration:
    swift run

## Status / open items

- Code was written without compiling; the first builds may need small fixes.
- Earlier version showed "not connected" even with the device plugged in;
  the device lookup was rewritten and a device picker + error text was added.
  Verify it now connects.
- Status-item popover works. Don't close NSStatusBarWindow at launch: the
  button moves to an off-screen window and NSPopover silently won't show.
- Confirm phono/line value mapping.

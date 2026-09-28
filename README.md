# Audio6

A native (Apple Silicon) macOS menu bar app for the **Native Instruments
Traktor Audio 6** audio interface. It replaces NI's Intel-only "Traktor Audio
6 Control Panel", which requires Rosetta to run.

Audio6 controls the input source (Phono/Line) and thru mode for each channel,
both live and as the power-on (startup) configuration — no Rosetta, no
bundled kernel extension, just a small status bar app talking directly to the
device over USB.

## Features

- Menu bar control, no Dock icon or main window
- Per-channel Phono/Line input switching
- Per-channel thru mode toggle
- Separate **Live** and **Startup** (power-on default) configuration, with a
  one-click "copy live settings to startup"
- Device picker, for when multiple compatible USB devices are present
- Auto-reconnect / polling so external changes (or a replug) are reflected

## Requirements

- macOS 13 or later, Apple Silicon
- A Native Instruments Traktor Audio 6 interface

## Install / run

```sh
./build-app.sh && open build/Audio6.app
```

For quick iteration during development:

```sh
swift run
```

## How it works

The app talks to the device using vendor-specific USB control requests
(reverse engineered from the original driver) rather than any NI SDK or
kernel extension. See [`CLAUDE.md`](CLAUDE.md) for the full protocol
breakdown, and [`ta6.py`](ta6.py) for a minimal `pyusb`-based reference
implementation of the same protocol.

## Project layout

- `Package.swift` — SwiftPM package, macOS 13+. Targets: `TA6USB` (C) and
  `Audio6` (Swift).
- `Sources/TA6USB/` — IOKit / IOUSBLib device lookup and USB control
  requests.
- `Sources/Audio6/` — the SwiftUI menu bar app.
- `Resources/Icon.icon` — Icon Composer app icon.
- `build-app.sh` — builds `build/Audio6.app` (bundles Info.plist, icon, and
  ad-hoc code signing).

## Status

This project is under active development; the Phono/Line value mapping in
particular hasn't been confirmed against real hardware for every unit. See
[`CLAUDE.md`](CLAUDE.md) for current open items.

## Disclaimer

Audio6 is an independent, unofficial project and is not affiliated with or
endorsed by Native Instruments. "Traktor" and "Traktor Audio 6" are
trademarks of Native Instruments GmbH.

## License

MIT — see [LICENSE](LICENSE).

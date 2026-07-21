# NetStatBar

A tiny native macOS menu bar app that shows current download and upload speed.

## Customization

Click the menu bar item to change:

- Update interval: 0.5, 1, 2, or 5 seconds.
- Display style: arrows, labels, compact, download only, or upload only.
- Units: bytes per second or bits per second.
- Scale: binary units (`KiB/MiB`) or decimal units (`KB/MB`).
- Interfaces: built-in `en*` network interfaces or all active non-loopback interfaces.
- Number display: rounded zero-unit values or one decimal place.

## Build

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
```

The app bundle is created at:

```text
build/NetStatBar.app
```

Open it from Finder or run:

```sh
open build/NetStatBar.app
```

## Install

To install it into `/Applications` and configure it to start when you log in:

```sh
chmod +x Scripts/install-app.sh
Scripts/install-app.sh
```

## Notes

- Native Swift/AppKit only. No Electron, no background web runtime.
- Samples macOS interface byte counters at the selected interval.
- Defaults to active `en*` interfaces, which covers built-in Wi-Fi and most Ethernet adapters on MacBooks while avoiding loopback and common virtual interfaces.
- Runs as a menu bar accessory app with no Dock icon.

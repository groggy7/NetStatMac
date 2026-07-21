# NetStatBar

NetStatBar is a small native macOS menu bar app that shows the current download and upload rate. It is built with Swift and AppKit, has no third-party dependencies, and runs without a Dock icon.

## Features

Click the menu bar readout to configure:

- **Update interval:** 0.5, 1, 2, or 5 seconds.
- **Display style:** arrows, labels, compact, download only, or upload only.
- **Item width:** automatic sizing, four presets, or a custom width from 60 to 250 points. Narrow dual-rate layouts automatically show download only.
- **Font size:** 10, 12, or 14 point presets, or a custom size from 9 to 18 points.
- **Units:** bytes per second (`KB/s`, `MB/s`, and so on) or bits per second (`Kb/s`, `Mb/s`, and so on). Units use decimal multiples.
- **Interfaces:** active `en*` interfaces or all active non-loopback interfaces.

Settings are saved in macOS user defaults and restored the next time the app starts. The menu also includes a reset-to-defaults action.

## How it works

At each update, NetStatBar reads the cumulative byte counters exposed by macOS for the selected network interfaces. It subtracts the previous counters and divides the difference by the actual elapsed time to calculate the current transfer rate.

The default interface mode includes active interfaces whose names begin with `en`, which normally covers a Mac's Wi-Fi, built-in Ethernet, and common Ethernet adapters while excluding loopback and most virtual interfaces. **All Active Interfaces** also includes VPN and other virtual interfaces, so tunneled traffic may be counted at more than one layer.

NetStatBar only reads interface-level byte totals. It does not inspect network contents, make network requests, require root access, or collect telemetry.

## Requirements

- macOS 14 or later.
- Xcode command-line tools with Swift 6 or later to build from source.

## Build

Compile a release executable with Swift Package Manager:

```sh
swift build -c release
```

The executable is created at `.build/release/NetStatBar`. Use the installer below to create and install a standard `.app` bundle.

## Test

Run the non-UI unit tests with Swift Package Manager:

```sh
swift test
```

The tests cover rate calculation, invalid samples, interface and counter changes, unit conversion, and display formatting. AppKit menu interactions are not included.

## Install and start at login

Run the included installer:

```sh
./install.sh
```

The installer:

1. Builds a release executable.
2. Creates and copies `NetStatBar.app` to `/Applications`.
3. Registers `~/Library/LaunchAgents/com.local.netstatbar.plist` so the app opens when you log in and restarts after an unsuccessful exit.
4. Starts the installed app.

If an existing copy is installed in `/Applications` and is not writable by the current user, the installer asks for administrator privileges to replace it. Rerun the same command to install a newer local build.

The login agent supervises the app executable directly. A crash or other unsuccessful exit is restarted after launchd's throttle interval; choosing **Quit** exits normally and leaves the app closed until it is opened again or you next log in.

The release executable is ad-hoc signed by the Swift toolchain. The installer does not perform distribution signing or notarization, so it is intended for personal installation rather than redistribution.

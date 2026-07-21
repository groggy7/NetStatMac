# NetStatBar

NetStatBar is a small native macOS menu bar app that shows the current download and upload rate. It is built with Swift and AppKit, has no third-party dependencies, and runs without a Dock icon.

## Features

Click the menu bar readout to configure:

- **Compact dashboard:** current download/upload rates, a 60-second activity graph, usage tracked today, this month, and this year, plus the three applications currently using the most bandwidth.
- **Appearance:** follow the system appearance or explicitly use light or dark mode.

- **Update interval:** 0.5, 1, 2, or 5 seconds.
- **Display style:** arrows, labels, compact, download only, or upload only.
- **Item width:** automatic sizing, four presets, or a custom width from 60 to 250 points. Narrow dual-rate layouts automatically show download only.
- **Font size:** 10, 12, or 14 point presets, or a custom size from 9 to 18 points.
- **Units:** bytes per second (`KB/s`, `MB/s`, and so on) or bits per second (`Kb/s`, `Mb/s`, and so on). Units use decimal multiples.
- **Interfaces:** automatic primary-route selection or all active hardware interfaces.

Settings are saved in macOS user defaults and restored the next time the app starts. The menu also includes a reset-to-defaults action.

The usage figures are local counters maintained by NetStatBar. They start when this version is installed, cover only periods when the app is running, and reset automatically at local day, month, and year boundaries. Download and upload details are available by hovering over a usage total, and usage history can be reset separately from preferences.

## How it works

At each update, NetStatBar reads the cumulative byte counters exposed by macOS for the selected network interfaces. It subtracts the previous counters and divides the difference by the actual elapsed time to calculate the current transfer rate.

The default **Automatic** mode follows macOS's primary IPv4 and IPv6 routes instead of guessing from interface names. When a VPN or other layered route is primary, NetStatBar counts active hardware transports instead, capturing both tunneled and direct traffic without adding the tunnel counters a second time. If no hardware transport exists, it falls back to the primary layered interface. **All Active Hardware** uses macOS's hardware-interface classifications, so unusual adapters are included while VPN tunnels and other virtual interfaces are excluded.

NetStatBar only reads interface-level byte totals. It does not inspect network contents, make network requests, require root access, or collect telemetry.

The activity graph keeps only the last 60 seconds of existing rate samples in memory. The top-process list is measured on demand with macOS's built-in `nettop` utility. It runs for one second only when the menu opens, groups helper processes under their owning app when possible, uses the owning application's icon, and does no process monitoring while the menu is closed.

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

The tests cover rate calculation, exact byte deltas, bounded graph history, usage-period rollovers and persistence, process-output parsing and aggregation, invalid samples, interface and counter changes, live system snapshots, unit conversion, status layout and settings behavior, and installer rollback. Direct AppKit menu interactions are not included.

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

The installer ad-hoc signs and verifies the completed app bundle. It does not perform Developer ID distribution signing or notarization, so it is intended for personal installation rather than redistribution.

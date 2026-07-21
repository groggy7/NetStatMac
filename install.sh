#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
SKIP_BUILD="${NETSTAT_SKIP_BUILD:-0}"
APP_NAME="NetStatBar.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APPLICATIONS_DIR="${NETSTAT_APPLICATIONS_DIR:-/Applications}"
TARGET_APP="$APPLICATIONS_DIR/$APP_NAME"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/NetStatBar"
STAGED_APP="$APPLICATIONS_DIR/.$APP_NAME.installing.$$"
BACKUP_APP="$APPLICATIONS_DIR/.$APP_NAME.backup.$$"
LAUNCH_AGENT_LABEL="${NETSTAT_LAUNCH_AGENT_LABEL:-com.local.netstatbar}"
LAUNCH_AGENT_DIR="${NETSTAT_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_LABEL.plist"
LAUNCH_AGENT_BACKUP="$LAUNCH_AGENT_DIR/.$LAUNCH_AGENT_LABEL.backup.$$"
LAUNCH_AGENT_TEMP=""
LAUNCHCTL="${NETSTAT_LAUNCHCTL:-launchctl}"
KILLALL="${NETSTAT_KILLALL:-killall}"
LSREGISTER="${NETSTAT_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister}"
TRANSACTION_ACTIVE=0
INSTALL_COMPLETE=0
APP_STOPPED=0
HAD_EXISTING_APP=0
HAD_EXISTING_LAUNCH_AGENT=0
LAUNCH_AGENT_REPLACED=0
INSTALL_WITH_SUDO=0

install_command() {
    if [ "$INSTALL_WITH_SUDO" -eq 1 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

cleanup() {
    local exit_status="$?"
    set +e

    if [ "$exit_status" -ne 0 ] && [ "$TRANSACTION_ACTIVE" -eq 1 ] && [ "$INSTALL_COMPLETE" -eq 0 ]; then
        echo "Installation failed; restoring the previous app..." >&2
        install_command rm -rf "$TARGET_APP"

        if [ "$HAD_EXISTING_APP" -eq 1 ] && [ -d "$BACKUP_APP" ]; then
            install_command mv "$BACKUP_APP" "$TARGET_APP"
        fi

        if [ "$LAUNCH_AGENT_REPLACED" -eq 1 ]; then
            rm -f "$LAUNCH_AGENT_PATH"
            if [ "$HAD_EXISTING_LAUNCH_AGENT" -eq 1 ] && [ -f "$LAUNCH_AGENT_BACKUP" ]; then
                mv "$LAUNCH_AGENT_BACKUP" "$LAUNCH_AGENT_PATH"
            fi
        fi

        if [ "$APP_STOPPED" -eq 1 ] && [ "$HAD_EXISTING_APP" -eq 1 ] && [ -f "$LAUNCH_AGENT_PATH" ]; then
            "$LAUNCHCTL" bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
            "$LAUNCHCTL" kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
        fi
    fi

    install_command rm -rf "$STAGED_APP"
    rm -rf "$APP_DIR"
    rm -f "$LAUNCH_AGENT_BACKUP"

    if [ -n "$LAUNCH_AGENT_TEMP" ]; then
        rm -f "$LAUNCH_AGENT_TEMP"
    fi

    trap - EXIT
    exit "$exit_status"
}

trap cleanup EXIT

cd "$ROOT_DIR"
if [ "$SKIP_BUILD" -eq 1 ]; then
    echo "Using existing NetStatBar build ($CONFIGURATION)..."
else
    echo "Building NetStatBar ($CONFIGURATION)..."
    swift build -c "$CONFIGURATION"
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/$CONFIGURATION/NetStatBar" "$MACOS_DIR/NetStatBar"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi

echo "Ad-hoc signing app bundle..."
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Prevent indexing of build directory to avoid double app detection
touch "$ROOT_DIR/build/.metadata_never_index"

echo "Preparing installation..."
mkdir -p "$APPLICATIONS_DIR"
mkdir -p "$LAUNCH_AGENT_DIR"

if [ ! -w "$(dirname "$TARGET_APP")" ]; then
    echo "Installing to /Applications requires administrator privileges..."
    sudo -v
    INSTALL_WITH_SUDO=1
fi

install_command cp -R "$APP_DIR" "$STAGED_APP"

echo "Verifying staged app signature..."
codesign --verify --deep --strict "$STAGED_APP"

LAUNCH_AGENT_TEMP="$(mktemp "$LAUNCH_AGENT_DIR/.$LAUNCH_AGENT_LABEL.XXXXXX")"
cat > "$LAUNCH_AGENT_TEMP" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_EXECUTABLE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$LAUNCH_AGENT_TEMP" >/dev/null
chmod 644 "$LAUNCH_AGENT_TEMP"

if [ -f "$LAUNCH_AGENT_PATH" ]; then
    HAD_EXISTING_LAUNCH_AGENT=1
    cp "$LAUNCH_AGENT_PATH" "$LAUNCH_AGENT_BACKUP"
fi

echo "Stopping the current NetStatBar instance..."
TRANSACTION_ACTIVE=1
"$LAUNCHCTL" bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
"$KILLALL" NetStatBar >/dev/null 2>&1 || true
APP_STOPPED=1

echo "Installing to /Applications..."
if [ -d "$TARGET_APP" ]; then
    HAD_EXISTING_APP=1
    install_command mv "$TARGET_APP" "$BACKUP_APP"
fi
install_command mv "$STAGED_APP" "$TARGET_APP"

echo "Verifying installed app signature..."
codesign --verify --deep --strict "$TARGET_APP"

mv "$LAUNCH_AGENT_TEMP" "$LAUNCH_AGENT_PATH"
LAUNCH_AGENT_TEMP=""
LAUNCH_AGENT_REPLACED=1

echo "Updating Launch Services registration..."
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP_DIR" || true
    "$LSREGISTER" -f "$TARGET_APP" || true
fi

echo "Restarting Launch Agent..."
"$LAUNCHCTL" bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
"$LAUNCHCTL" kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL"
"$LAUNCHCTL" print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null

INSTALL_COMPLETE=1
install_command rm -rf "$BACKUP_APP" || true
rm -f "$LAUNCH_AGENT_BACKUP"

echo "Successfully installed and started $TARGET_APP"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="NetStatBar.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
TARGET_APP="/Applications/$APP_NAME"
LAUNCH_AGENT_LABEL="com.local.netstatbar"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_LABEL.plist"

echo "Stopping any running instances of NetStatBar..."
killall NetStatBar >/dev/null 2>&1 || true

echo "Building NetStatBar ($CONFIGURATION)..."
cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/$CONFIGURATION/NetStatBar" "$MACOS_DIR/NetStatBar"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi

# Prevent indexing of build directory to avoid double app detection
touch "$ROOT_DIR/build/.metadata_never_index"

echo "Installing to /Applications..."
mkdir -p "$LAUNCH_AGENT_DIR"

# Remove target app. If permission is denied, run with sudo.
if [ -d "$TARGET_APP" ]; then
    if [ -w "$TARGET_APP" ]; then
        rm -rf "$TARGET_APP"
    else
        echo "Removing previous installation (requires sudo privileges)..."
        sudo rm -rf "$TARGET_APP"
    fi
fi

cp -R "$APP_DIR" "$TARGET_APP"

echo "Updating Launch Services registration..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP_DIR" || true
    "$LSREGISTER" -f "$TARGET_APP" || true
fi

# Remove the built app bundle from the project directory so it's not indexed
rm -rf "$APP_DIR"

echo "Configuring Launch Agent..."
cat > "$LAUNCH_AGENT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$TARGET_APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
</dict>
</plist>
PLIST

echo "Restarting Launch Agent..."
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL"

echo "Successfully installed and started $TARGET_APP"

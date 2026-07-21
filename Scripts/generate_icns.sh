#!/usr/bin/env bash
# Scripts/generate_icns.sh
# Usage: ./generate_icns.sh <path_to_source_png>

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_source_png>"
    exit 1
fi

SOURCE_PNG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PROJECT_ROOT/Resources"
TEMP_ICONSET="$RESOURCES_DIR/AppIcon.iconset"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "Error: Source image file not found at $SOURCE_PNG"
    exit 1
fi

echo "Creating temporary iconset directory: $TEMP_ICONSET"
mkdir -p "$TEMP_ICONSET"

# Helper function to resize using sips
resize_icon() {
    local size="$1"
    local output_name="$2"
    echo "Creating $output_name (${size}x${size})..."
    sips -s format png -z "$size" "$size" "$SOURCE_PNG" --out "$TEMP_ICONSET/$output_name" > /dev/null
}

# Generate all standard sizes for macOS app icons
resize_icon 16 "icon_16x16.png"
resize_icon 32 "icon_16x16@2x.png"
resize_icon 32 "icon_32x32.png"
resize_icon 64 "icon_32x32@2x.png"
resize_icon 128 "icon_128x128.png"
resize_icon 256 "icon_128x128@2x.png"
resize_icon 256 "icon_256x256.png"
resize_icon 512 "icon_256x256@2x.png"
resize_icon 512 "icon_512x512.png"
resize_icon 1024 "icon_512x512@2x.png"

echo "Compiling .icns file using iconutil..."
iconutil -c icns "$TEMP_ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"

echo "Cleaning up temporary iconset..."
rm -rf "$TEMP_ICONSET"

echo "Successfully generated $RESOURCES_DIR/AppIcon.icns!"
ls -lh "$RESOURCES_DIR/AppIcon.icns"

#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh /path/to/App.app output.dmg}"
OUTPUT_DMG="${2:?Usage: create-dmg.sh /path/to/App.app output.dmg}"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Darwin Cleaner" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DMG"


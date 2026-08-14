#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.6.0"
INSTALL=0
DMG=0
OUT_DMG=""

usage() {
  echo "Usage: $0 [--version X.Y.Z] [--install] [--dmg] [--dmg-out PATH]"
  echo "  --version   set CFBundleVersion / CFBundleShortVersionString (default $VERSION)"
  echo "  --install   copy the built app to /Applications and register it"
  echo "  --dmg       also create a DMG (default: dist/DeepSeek Harness.dmg)"
  echo "  --dmg-out   override the DMG output path"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --dmg) DMG=1; shift ;;
    --dmg-out) OUT_DMG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

APP_NAME="DeepSeek Harness"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling main.swift (version $VERSION)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -framework Cocoa -framework WebKit -o "$APP/Contents/MacOS/DeepSeekHarness" main.swift

echo "==> Assembling bundle"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"

echo "==> Signing"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [ $INSTALL -eq 1 ]; then
  echo "==> Installing to /Applications"
  DST="/Applications/$APP_NAME.app"
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  sleep 1
  rm -rf "$DST"
  cp -pR "$APP" "$DST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DST" 2>/dev/null || true
  echo "==> Installed $DST ($VERSION)"
fi

if [ $DMG -eq 1 ]; then
  echo "==> Building DMG"
  mkdir -p dist
  STAGE="$BUILD_DIR/stage"
  mkdir -p "$STAGE"
  cp -pR "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  if [ -z "$OUT_DMG" ]; then
    DMG_PATH="dist/$APP_NAME.dmg"
  else
    DMG_PATH="$OUT_DMG"
  fi
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
  echo "==> DMG written to $DMG_PATH"
  if [ "$DMG_PATH" != "$HOME/Desktop/$APP_NAME.dmg" ]; then
    cp "$DMG_PATH" "$HOME/Desktop/$APP_NAME.dmg"
    echo "==> Copied DMG to $HOME/Desktop/$APP_NAME.dmg"
  fi
fi

echo "==> Done."

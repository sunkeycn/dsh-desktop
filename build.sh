#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
PET_VERSION="0.1.8"
SIDEBAR_VERSION="0.15.2"
FRP_PLUGIN_VERSION="0.2.0"
FRP_VERSION="0.71.0"
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
swiftc -swift-version 5 -O -framework Cocoa -framework WebKit -o "$APP/Contents/MacOS/DeepSeekHarness" main.swift PluginManager.swift

echo "==> Assembling bundle"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
cp plugin-catalog.json "$APP/Contents/Resources/plugin-catalog.json"
mkdir -p "$APP/Contents/Resources/Scripts"
cp scripts/migrate-profile.cjs "$APP/Contents/Resources/Scripts/migrate-profile.cjs"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"

echo "==> Packing bundled plugins"
SEED_DIR="$APP/Contents/Resources/PluginSeeds"
mkdir -p "$SEED_DIR"
if [ -x "$HOME/Library/Application Support/DeepSeek Harness/runtime/node/bin/npm" ]; then
  NPM="$HOME/Library/Application Support/DeepSeek Harness/runtime/node/bin/npm"
else
  NPM="$(command -v npm)"
fi
"$NPM" pack "dsh-pet@$PET_VERSION" --silent --pack-destination "$SEED_DIR" >/dev/null
"$NPM" pack "dsh-better-sidebar@$SIDEBAR_VERSION" --silent --pack-destination "$SEED_DIR" >/dev/null
"$NPM" pack ./plugins/dsh-frp-remote --silent --pack-destination "$SEED_DIR" >/dev/null
test -f "$SEED_DIR/dsh-pet-$PET_VERSION.tgz"
test -f "$SEED_DIR/dsh-better-sidebar-$SIDEBAR_VERSION.tgz"
test -f "$SEED_DIR/dsh-frp-remote-$FRP_PLUGIN_VERSION.tgz"

# Add HEVC-with-alpha assets and WebKit source selection to the bundled pet while
# retaining the original VP9-alpha WebM files for Chromium browsers.
PET_STAGE="$BUILD_DIR/pet-seed"
mkdir -p "$PET_STAGE"
tar -xzf "$SEED_DIR/dsh-pet-$PET_VERSION.tgz" -C "$PET_STAGE"
DSH_PET_DIR="$PET_STAGE/package" plugins/dsh-pet/install.sh
tar -czf "$SEED_DIR/dsh-pet-$PET_VERSION.tgz" -C "$PET_STAGE" package

# The published sidebar already contains compiled lib files. Its `prepare` hook is only
# for source checkouts and makes pnpm require an approval tied to the App's absolute path.
SIDEBAR_STAGE="$BUILD_DIR/sidebar-seed"
mkdir -p "$SIDEBAR_STAGE"
tar -xzf "$SEED_DIR/dsh-better-sidebar-$SIDEBAR_VERSION.tgz" -C "$SIDEBAR_STAGE"
node scripts/sanitize-plugin-seed.cjs "$SIDEBAR_STAGE/package/package.json"
tar -czf "$SEED_DIR/dsh-better-sidebar-$SIDEBAR_VERSION.tgz" -C "$SIDEBAR_STAGE" package

echo "==> Bundling frpc $FRP_VERSION"
case "$(uname -m)" in
  arm64)
    FRP_ARCH="arm64"
    FRP_SHA256="45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6"
    ;;
  x86_64)
    FRP_ARCH="amd64"
    FRP_SHA256="1b1b4e2f1836e21e8733f1dddaacd4ed9ae67d7dbee39046b9d7b7eda6253637"
    ;;
  *)
    echo "unsupported architecture for frpc: $(uname -m)" >&2
    exit 1
    ;;
esac
FRP_ARCHIVE="$BUILD_DIR/frp.tar.gz"
FRP_EXTRACT="$BUILD_DIR/frp"
curl -fL --retry 3 --connect-timeout 15 \
  "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_darwin_${FRP_ARCH}.tar.gz" \
  -o "$FRP_ARCHIVE"
ACTUAL_FRP_SHA256="$(shasum -a 256 "$FRP_ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_FRP_SHA256" != "$FRP_SHA256" ]; then
  echo "frpc archive checksum mismatch" >&2
  exit 1
fi
mkdir -p "$FRP_EXTRACT" "$APP/Contents/Resources/FRP"
tar -xzf "$FRP_ARCHIVE" -C "$FRP_EXTRACT"
cp "$FRP_EXTRACT/frp_${FRP_VERSION}_darwin_${FRP_ARCH}/frpc" "$APP/Contents/Resources/FRP/frpc"
chmod 755 "$APP/Contents/Resources/FRP/frpc"

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

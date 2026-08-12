#!/bin/bash
# Builds TheReadingRoom.app.
#
#   ./build.sh              release build, universal, into build/
#   ./build.sh --install    also copy to /Applications
#   ./build.sh --debug      faster debug build, native arch only
#   ./build.sh --run        build then launch

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="The Reading Room"
BINARY="TheReadingRoom"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

CONFIG="release"
ARCH_FLAGS=(--arch arm64 --arch x86_64)
INSTALL=0
RUN=0

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    --debug) CONFIG="debug"; ARCH_FLAGS=() ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
EXECUTABLE="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/$BINARY"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$EXECUTABLE" "$APP/Contents/MacOS/$BINARY"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/TheReadingRoomCore/Resources/* "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# Prefer the supplied artwork (largest master available); fall back to the
# procedural icon if the art folder is missing.
ICON_MASTER="reading-room-icons/reading-room-512.png"
if [ -f "$ICON_MASTER" ]; then
  echo "    from $ICON_MASTER"
  # Rasterize every size an .iconset needs from the one master.
  for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" "$ICON_MASTER" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    d=$((sz * 2))
    sips -z "$d" "$d" "$ICON_MASTER" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
else
  echo "    no artwork found — generating procedural icon"
  swift Tools/make-icon.swift "$ICONSET" > /dev/null
fi
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Identity selection, best-for-distribution first. Override with SIGN_IDENTITY=…
#   1. $SIGN_IDENTITY            explicit override
#   2. "Developer ID Application"  notarizable, Gatekeeper-accepted on any Mac
#   3. "Apple Development"          Notification Center works; valid only on this
#                                  and registered Macs (not for distribution)
#   4. ad-hoc ("-")                CI fallback; notifications are unreliable
# ("Apple Distribution" is skipped on purpose: a distribution-signed Mac app
# needs an embedded provisioning profile to launch.)
if [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIGN_IDENTITY"
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')
  [ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')
  [ -z "$IDENTITY" ] && IDENTITY="-"
fi

# The hardened runtime is required to notarize, and only makes sense for a
# Developer ID build — add it there, skip it for dev/ad-hoc signing.
SIGN_OPTS=(--force --sign "$IDENTITY")
case "$IDENTITY" in
  *"Developer ID Application"*) SIGN_OPTS+=(--options runtime) ;;
esac

echo "==> Signing with: $IDENTITY"
# A secure timestamp keeps the signature valid past the certificate's expiry and
# is required for notarization; it needs the network, so fall back if unreachable.
codesign "${SIGN_OPTS[@]}" --timestamp "$APP" 2>/dev/null \
  || codesign "${SIGN_OPTS[@]}" --timestamp=none "$APP"

codesign --verify --strict "$APP" && echo "    signature verified"

if [ "$INSTALL" = "1" ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  APP="/Applications/$APP_NAME.app"
fi

echo "==> Done: $APP"
[ "$RUN" = "1" ] && open "$APP"
exit 0

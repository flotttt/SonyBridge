#!/bin/bash
# Builds build/SonyBridge.app with the Command Line Tools only (no Xcode needed).
#   CONFIG=debug|release (default: debug)
#   ARCHS="arm64 x86_64"  (default: this Mac's architecture; several = universal binary via lipo)
#   DEBUG_PROTOCOL=1      (hex-dumps every frame exchanged with the headphones to stderr)
set -euo pipefail
shopt -s nullglob

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORE=$ROOT/Client
MAC=$CORE/macos
OUT=$ROOT/build
APP=$OUT/SonyBridge.app
SDK=$(xcrun --show-sdk-path)
CONFIG=${CONFIG:-debug}
ARCHS=${ARCHS:-$(uname -m)}
MIN_MACOS=13.0

if [ "$CONFIG" = release ]; then SWIFT_OPT="-O"; CXX_OPT="-O2"; else SWIFT_OPT="-Onone -g"; CXX_OPT="-O0 -g"; fi
SWIFT_DEFINES=""; CXX_DEFINES=""
if [ "${DEBUG_PROTOCOL:-0}" = 1 ]; then SWIFT_DEFINES="-D DEBUG_PROTOCOL"; CXX_DEFINES="-DSHC_DEBUG_PROTOCOL"; fi

SWIFT_SOURCES=("$MAC"/*.swift "$MAC"/MenuRows/*.swift)
CXX_SOURCES=("$CORE"/*.cpp)
OBJCXX_SOURCES=("$MAC"/*.mm)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARIES=""

for ARCH in $ARCHS; do
    OBJ=$OUT/obj/$CONFIG-$ARCH
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    TARGET=$ARCH-apple-macos$MIN_MACOS
    CXXFLAGS="-target $TARGET -isysroot $SDK -std=c++17 $CXX_OPT $CXX_DEFINES -I $CORE -I $MAC"

    echo "== [$ARCH] Swift"
    swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 $SWIFT_OPT $SWIFT_DEFINES -wmo -parse-as-library \
        -module-name SonyBridge \
        -import-objc-header "$MAC/SonyHeadphonesClient-Bridging-Header.h" -I "$MAC" -I "$CORE" \
        -c "${SWIFT_SOURCES[@]}" -o "$OBJ/swift.o"

    echo "== [$ARCH] C++"
    for f in "${CXX_SOURCES[@]}"; do clang++ $CXXFLAGS -c "$f" -o "$OBJ/$(basename "$f" .cpp).o"; done

    echo "== [$ARCH] Obj-C++"
    for f in "${OBJCXX_SOURCES[@]}"; do
        clang++ $CXXFLAGS -fobjc-arc -fmodules -fcxx-modules -c "$f" -o "$OBJ/$(basename "$f" .mm).o"
    done

    echo "== [$ARCH] Link"
    swiftc -target "$TARGET" -sdk "$SDK" "$OBJ"/*.o -o "$OBJ/SonyBridge" -lc++ \
        -framework AppKit -framework SwiftUI -framework Combine -framework IOBluetooth \
        -framework IOBluetoothUI -framework ServiceManagement
    BINARIES="$BINARIES $OBJ/SonyBridge"
done

lipo -create $BINARIES -output "$APP/Contents/MacOS/SonyBridge"

echo "== Resources"
cp "$MAC/info.plist" "$APP/Contents/Info.plist"
cp -R "$MAC"/*.lproj "$APP/Contents/Resources/"
iconutil -c icns "$MAC/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "== Sign (ad-hoc)"
codesign --force --sign - --entitlements "$MAC/SonyHeadphonesClient.entitlements" "$APP"
echo "OK -> $APP"

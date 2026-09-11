#!/bin/bash
# Builds and runs the unit test executables (plain asserts, no XCTest), then checks the translations.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAC=$ROOT/Client/macos
OUT=$ROOT/build/tests
SDK=$(xcrun --show-sdk-path)
TARGET=$(uname -m)-apple-macos13.0
mkdir -p "$OUT"

echo "== LogicTests"
swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 \
    "$ROOT/Client/tests/LogicTests/main.swift" \
    "$MAC/ReconnectPolicy.swift" "$MAC/PollGuard.swift" "$MAC/SendThrottle.swift" \
    -o "$OUT/LogicTests"
"$OUT/LogicTests"

echo "== ProtocolParsersTests"
clang++ -target "$TARGET" -isysroot "$SDK" -std=c++17 -I "$ROOT/Client" \
    "$ROOT/Client/tests/ProtocolParsersTests.cpp" "$ROOT/Client/ProtocolParsers.cpp" \
    "$ROOT/Client/CommandSerializer.cpp" "$ROOT/Client/ByteMagic.cpp" \
    -o "$OUT/ProtocolParsersTests"
"$OUT/ProtocolParsersTests"

echo "== BluetoothWrapperTests"
clang++ -target "$TARGET" -isysroot "$SDK" -std=c++17 -I "$ROOT/Client" \
    "$ROOT/Client/tests/BluetoothWrapperTests.cpp" "$ROOT/Client/BluetoothWrapper.cpp" \
    "$ROOT/Client/CommandSerializer.cpp" "$ROOT/Client/ByteMagic.cpp" \
    -o "$OUT/BluetoothWrapperTests"
"$OUT/BluetoothWrapperTests"

echo "== HeadphonesTests"
clang++ -target "$TARGET" -isysroot "$SDK" -std=c++17 -I "$ROOT/Client" \
    "$ROOT/Client/tests/HeadphonesTests.cpp" "$ROOT/Client/Headphones.cpp" "$ROOT/Client/ProtocolParsers.cpp" \
    "$ROOT/Client/BluetoothWrapper.cpp" "$ROOT/Client/CommandSerializer.cpp" "$ROOT/Client/ByteMagic.cpp" \
    -o "$OUT/HeadphonesTests"
"$OUT/HeadphonesTests"

echo "== Localization"
python3 "$ROOT/scripts/check_localization.py"

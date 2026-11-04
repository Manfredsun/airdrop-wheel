#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Building AirDrop Wheel 2 in Release configuration..."
xcodebuild -project "AirDrop Wheel 2.xcodeproj" \
    -scheme "AirDrop Wheel 2" \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    -quiet

DERIVED_APP="build/DerivedData/Build/Products/Release/AirDrop Wheel 2.app"

if [ ! -d "$DERIVED_APP" ]; then
    echo "Error: Built app not found at $DERIVED_APP"
    exit 1
fi

mkdir -p dist
rm -rf "dist/AirDrop Wheel 2.app" "AirDrop Wheel 2.app"
cp -R "$DERIVED_APP" "dist/AirDrop Wheel 2.app"
cp -R "$DERIVED_APP" "AirDrop Wheel 2.app"

echo "==> Signing app with stable Designated Requirement (identifier \"app.airdropwheel2.macos\")..."
codesign --force --deep -s - \
    -i "app.airdropwheel2.macos" \
    -r '=designated => identifier "app.airdropwheel2.macos"' \
    "dist/AirDrop Wheel 2.app"

codesign --force --deep -s - \
    -i "app.airdropwheel2.macos" \
    -r '=designated => identifier "app.airdropwheel2.macos"' \
    "AirDrop Wheel 2.app"

echo "==> Verifying code signature..."
codesign -dvvv "AirDrop Wheel 2.app" 2>&1 | grep -E "Identifier|Signature|Internal requirements"
codesign -d -r- "AirDrop Wheel 2.app"

echo "==> Build and signing complete: AirDrop Wheel 2.app is ready."

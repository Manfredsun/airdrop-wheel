#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Building AirDrop Wheel in Release configuration..."
xcodebuild -project "AirDrop Wheel.xcodeproj" \
    -scheme "AirDrop Wheel" \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    -quiet

DERIVED_APP="build/DerivedData/Build/Products/Release/AirDrop Wheel.app"

if [ ! -d "$DERIVED_APP" ]; then
    echo "Error: Built app not found at $DERIVED_APP"
    exit 1
fi

mkdir -p dist
rm -rf "dist/AirDrop Wheel.app" "AirDrop Wheel.app" "dist/AirDrop Wheel 2.app" "AirDrop Wheel 2.app"
cp -R "$DERIVED_APP" "dist/AirDrop Wheel.app"
cp -R "$DERIVED_APP" "AirDrop Wheel.app"

echo "==> Signing app with stable Designated Requirement (identifier \"app.airdropwheel.macos\")..."
codesign --force --deep -s - \
    -i "app.airdropwheel.macos" \
    -r '=designated => identifier "app.airdropwheel.macos"' \
    "dist/AirDrop Wheel.app"

codesign --force --deep -s - \
    -i "app.airdropwheel.macos" \
    -r '=designated => identifier "app.airdropwheel.macos"' \
    "AirDrop Wheel.app"

echo "==> Verifying code signature..."
codesign -dvvv "AirDrop Wheel.app" 2>&1 | grep -E "Identifier|Signature|Internal requirements"
codesign -d -r- "AirDrop Wheel.app"

echo "==> Build and signing complete: AirDrop Wheel.app is ready."

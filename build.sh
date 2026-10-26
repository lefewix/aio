#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release
APP=build/AIO.app
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/AIO" "$APP/Contents/MacOS/AIO"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
clang -arch arm64 -dynamiclib -fobjc-arc -framework Foundation -Wall -o "$APP/Contents/Resources/nowplaying.dylib" Helper/nowplaying.m
cp Helper/nowplaying.pl "$APP/Contents/Resources/"

ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
ID=${ID:--}
echo "Signing with: $([ "$ID" = - ] && echo ad-hoc || echo "$ID")"
codesign --force --sign - "$APP/Contents/Resources/nowplaying.dylib"
codesign --force --sign "$ID" "$APP"

if [ "$1" = "--install" ]; then
    ditto "$APP" /Applications/AIO.app
    echo "Installed to /Applications/AIO.app"
fi

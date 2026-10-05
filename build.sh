#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/MyPorts.app/Contents/{MacOS,Resources}
MACOS_SDK="$(xcrun --show-sdk-path)"
for BUILD_ARCH in arm64 x86_64; do
    xcrun clang -O2 -Wall -Wextra -arch "$BUILD_ARCH" -mmacosx-version-min=13.0 -isysroot "$MACOS_SDK" -c Sources/PortScanner.c -o "build/PortScanner-$BUILD_ARCH.o"
    xcrun swiftc -O -swift-version 5 -target "$BUILD_ARCH-apple-macosx13.0" -sdk "$MACOS_SDK" -import-objc-header Sources/PortScanner.h Sources/main.swift Sources/PortIcon.swift "build/PortScanner-$BUILD_ARCH.o" -framework AppKit -framework ServiceManagement -o "build/MyPorts-$BUILD_ARCH"
done
cp "build/PortScanner-$(uname -m).o" build/PortScanner.o
xcrun lipo -create build/MyPorts-arm64 build/MyPorts-x86_64 -output build/MyPorts.app/Contents/MacOS/MyPorts
xcrun swiftc -O Sources/PortIcon.swift Sources/IconGenerator/main.swift -o build/make-icon
./build/make-icon build/MyPorts.iconset
iconutil -c icns build/MyPorts.iconset -o build/MyPorts.app/Contents/Resources/MyPorts.icns
cp Info.plist build/MyPorts.app/Contents/Info.plist
codesign --force --sign - --identifier local.angel.puertos build/MyPorts.app
echo "Universal app ready: $PWD/build/MyPorts.app"

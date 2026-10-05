#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/Puertos.app/Contents/{MacOS,Resources}
MACOS_SDK="$(xcrun --show-sdk-path)"
for BUILD_ARCH in arm64 x86_64; do
    xcrun clang -O2 -Wall -Wextra -arch "$BUILD_ARCH" -mmacosx-version-min=13.0 -isysroot "$MACOS_SDK" -c Sources/PortScanner.c -o "build/PortScanner-$BUILD_ARCH.o"
    xcrun swiftc -O -swift-version 5 -target "$BUILD_ARCH-apple-macosx13.0" -sdk "$MACOS_SDK" -import-objc-header Sources/PortScanner.h Sources/main.swift Sources/PortIcon.swift "build/PortScanner-$BUILD_ARCH.o" -framework AppKit -framework ServiceManagement -o "build/Puertos-$BUILD_ARCH"
done
cp "build/PortScanner-$(uname -m).o" build/PortScanner.o
xcrun lipo -create build/Puertos-arm64 build/Puertos-x86_64 -output build/Puertos.app/Contents/MacOS/Puertos
xcrun swiftc -O Sources/PortIcon.swift Sources/IconGenerator/main.swift -o build/make-icon
./build/make-icon build/Puertos.iconset
iconutil -c icns build/Puertos.iconset -o build/Puertos.app/Contents/Resources/Puertos.icns
cp Info.plist build/Puertos.app/Contents/Info.plist
codesign --force --sign - --identifier local.angel.puertos build/Puertos.app
echo "Aplicación universal lista: $PWD/build/Puertos.app"

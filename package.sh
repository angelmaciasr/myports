#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
codesign --verify --deep --strict build/Puertos.app
ARCHIVE="Puertos-macos-universal.zip"
rm -f "build/$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/Puertos.app "build/$ARCHIVE"
(cd build && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Descarga lista: $PWD/build/$ARCHIVE"

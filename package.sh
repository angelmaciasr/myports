#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
codesign --verify --deep --strict build/MyPorts.app
ARCHIVE="MyPorts-macos-universal.zip"
rm -f "build/$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/MyPorts.app "build/$ARCHIVE"
(cd build && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Download ready: $PWD/build/$ARCHIVE"

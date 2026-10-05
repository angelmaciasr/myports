#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x build/MyPorts.app/Contents/MacOS/MyPorts ]]; then ./build.sh; fi
DEST="$HOME/Applications/MyPorts.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DEST" ]]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$ID" != "local.angel.puertos" ]]; then
        echo "Another application already exists at $DEST. It has not been replaced." >&2
        exit 1
    fi
fi
/usr/bin/ditto build/MyPorts.app "$DEST"
if [[ ! -e "$HOME/Desktop/MyPorts.app" && ! -L "$HOME/Desktop/MyPorts.app" ]]; then
    ln -s "$DEST" "$HOME/Desktop/MyPorts.app"
fi
open "$DEST" --args --show
echo "Installed at $DEST. Available from the desktop, Spotlight and menu bar."

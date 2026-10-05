#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x build/Puertos.app/Contents/MacOS/Puertos ]]; then ./build.sh; fi
DEST="$HOME/Applications/Puertos.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DEST" ]]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$ID" != "local.angel.puertos" ]]; then
        echo "Ya existe otra aplicación en $DEST. No se ha reemplazado." >&2
        exit 1
    fi
fi
/usr/bin/ditto build/Puertos.app "$DEST"
if [[ ! -e "$HOME/Desktop/Puertos.app" && ! -L "$HOME/Desktop/Puertos.app" ]]; then
    ln -s "$DEST" "$HOME/Desktop/Puertos.app"
fi
open "$DEST" --args --show
echo "Instalada en $DEST. Disponible desde el escritorio, Spotlight y la barra de menú."

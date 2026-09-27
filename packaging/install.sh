#!/bin/sh
# Installs a release build of Look In for the current user (or system-wide
# with PREFIX=/usr/local and sudo).
#
#   flutter build linux --release
#   ./packaging/install.sh            # installs into ~/.local
#   ./packaging/install.sh --uninstall
set -eu

PREFIX=${PREFIX:-$HOME/.local}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APP_DIR="$PREFIX/lib/look-in"
BIN="$PREFIX/bin/look_in"
DESKTOP="$PREFIX/share/applications/systems.fu.look_in.desktop"

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP_DIR"
  rm -f "$BIN" "$DESKTOP"
  echo "Look In removed from $PREFIX (your mail data in ~/.local/share/systems.fu.look_in was kept)."
  exit 0
fi

if [ ! -x "$BUNDLE/look_in" ]; then
  echo "No release build found. Run 'flutter build linux --release' first." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$PREFIX/bin" "$(dirname "$DESKTOP")"
cp -R "$BUNDLE/." "$APP_DIR/"
ln -sf "$APP_DIR/look_in" "$BIN"
sed "s|^Exec=look_in|Exec=$APP_DIR/look_in|" \
  "$ROOT/packaging/systems.fu.look_in.desktop" > "$DESKTOP"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$(dirname "$DESKTOP")" >/dev/null 2>&1 || true
fi

echo "Installed Look In to $APP_DIR"
echo "Start it from your applications menu or run: $BIN"

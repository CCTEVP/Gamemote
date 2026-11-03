#!/usr/bin/env bash
# Links the iOS-simulator slices of our static library and godot-cpp into a tiny
# executable WITHOUT passing -framework CoreBluetooth. This only succeeds if the
# auto-link directive works, which is what the Godot-generated Xcode project relies on.
set -euo pipefail
cd "$(dirname "$0")/../../.."
BIN=app/addons/gamemote_ble/bin
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
EXT=$(find "$BIN/libgamemote_ble.ios.template_debug.xcframework" -path "*simulator*" -name "*.a" | head -1)
CPP=$(find "$BIN/libgodot-cpp.ios.template_debug.xcframework" -path "*simulator*" -name "*.a" | head -1)
TMP=$(mktemp -d)
cat > "$TMP/main.c" <<'C'
extern int gamemote_ble_library_init(void *, void *, void *);
int main(void) { return (int)(long)&gamemote_ble_library_init == 0; }
C
xcrun --sdk iphonesimulator clang -arch arm64 -isysroot "$SDK" -mios-simulator-version-min=14.0 \
  "$TMP/main.c" "$EXT" "$CPP" -lc++ -o "$TMP/link_test"
echo "link OK: CoreBluetooth resolved via auto-linking"

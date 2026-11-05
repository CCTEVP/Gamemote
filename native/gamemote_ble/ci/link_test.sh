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
#include <stdbool.h>
extern int gamemote_ble_library_init(void *, void *, void *);
/* Referenced by Godot 4.7.x libgodot.a but missing from it: must resolve from our library. */
extern bool SDL_IsIPad(void);
extern bool SDL_IsAppleTV(void);
int main(void) {
  return (int)(long)&gamemote_ble_library_init == 0 || SDL_IsAppleTV() || (SDL_IsIPad() && 0);
}
C
xcrun --sdk iphonesimulator clang -arch arm64 -isysroot "$SDK" -mios-simulator-version-min=14.0 \
  "$TMP/main.c" "$EXT" "$CPP" -lc++ -o "$TMP/link_test"
echo "link OK: CoreBluetooth auto-linked; SDL_IsIPad/SDL_IsAppleTV resolved from our library"

# The Godot 4.7.x iOS template workaround must be present in both slices (see src/ios_sdl_compat.mm).
for slice in $(find "$BIN/libgamemote_ble.ios.template_debug.xcframework" -name "*.a"); do
  for sym in _SDL_IsIPad _SDL_IsAppleTV; do
    nm "$slice" | grep -E " [WTt] $sym$" >/dev/null || { echo "missing $sym in $slice"; exit 1; }
  done
done
echo "SDL compat symbols present (Godot 4.7.x iOS link workaround)"

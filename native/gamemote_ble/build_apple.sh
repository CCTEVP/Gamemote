#!/usr/bin/env bash
# Build the GamemoteBle extension for iOS/iPadOS (device + simulator) and macOS.
# Run on a Mac with Xcode installed:
#
#   ./native/gamemote_ble/build_apple.sh
#
# Output goes to app/addons/gamemote_ble/bin/. The first run takes a few minutes
# (it compiles godot-cpp); later runs are incremental.
#
# Options (environment variables):
#   TARGETS="template_debug"   build only debug (default: debug and release)
#   MACOS_ARCH=universal       macOS slice architecture (default: this Mac's arch)
#   SKIP_MACOS=1               only build iOS
set -euo pipefail

cd "$(dirname "$0")"
BIN=../../app/addons/gamemote_ble/bin
TARGETS=${TARGETS:-"template_debug template_release"}
MACOS_ARCH=${MACOS_ARCH:-$(uname -m)}
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

if [[ "$(uname)" != "Darwin" ]]; then
  echo "build_apple.sh must run on macOS (it needs Xcode)." >&2
  exit 1
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "Xcode iOS SDK not found. Install Xcode, open it once, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

if [[ ! -f godot-cpp/SConstruct ]]; then
  echo "==> Fetching godot-cpp submodule"
  git submodule update --init --depth 1 godot-cpp
fi

if command -v scons >/dev/null 2>&1; then
  SCONS=scons
else
  if [[ ! -x .venv/bin/scons ]]; then
    echo "==> Installing SCons into native/gamemote_ble/.venv"
    python3 -m venv .venv
    .venv/bin/pip install --quiet scons
  fi
  SCONS=.venv/bin/scons
fi

mkdir -p "$BIN"
for target in $TARGETS; do
  echo "==> iOS device ($target)"
  $SCONS -j"$JOBS" platform=ios arch=arm64 ios_simulator=no target="$target"
  echo "==> iOS simulator ($target)"
  $SCONS -j"$JOBS" platform=ios arch=universal ios_simulator=yes target="$target"

  echo "==> Packaging iOS xcframeworks ($target)"
  rm -rf "$BIN/libgamemote_ble.ios.$target.xcframework" "$BIN/libgodot-cpp.ios.$target.xcframework"
  xcodebuild -create-xcframework \
    -library "$BIN/libgamemote_ble.ios.$target.a" \
    -library "$BIN/libgamemote_ble.ios.$target.simulator.a" \
    -output "$BIN/libgamemote_ble.ios.$target.xcframework" >/dev/null
  xcodebuild -create-xcframework \
    -library "godot-cpp/bin/libgodot-cpp.ios.$target.arm64.a" \
    -library "godot-cpp/bin/libgodot-cpp.ios.$target.universal.simulator.a" \
    -output "$BIN/libgodot-cpp.ios.$target.xcframework" >/dev/null
  rm -f "$BIN/libgamemote_ble.ios.$target.a" "$BIN/libgamemote_ble.ios.$target.simulator.a"

  if [[ -z "${SKIP_MACOS:-}" ]]; then
    echo "==> macOS $MACOS_ARCH ($target)"
    $SCONS -j"$JOBS" platform=macos arch="$MACOS_ARCH" target="$target"
  fi
done

echo
echo "Done. Built files:"
ls -1 "$BIN"

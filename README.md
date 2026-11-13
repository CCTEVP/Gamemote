# Gamemote

A native iPhone/iPad app (SwiftUI + RealityKit) that remote-controls a Bluetooth LE
microcontroller:

- **Live control:** a clay game controller bound to the device's channels and actions, with a
  console that shows what is sent and what the gadget answers.
- **Routines:** sequences built in a Scratch-like block editor. They run either from the app
  (**Live**) or are uploaded to the board and keep running on their own (**Transferred**).

**Status:** native port, trial stage. Home and Live work against the in-app mock device; the
Bluetooth transport and the routine builder are being ported next. The previous Godot app is
complete on the [`Godot`](https://github.com/CCTEVP/Gamemote/tree/Godot) branch.

## Open in Xcode

Requires Xcode 16 or newer (iOS 18 SDK).

```bash
open ios/Gamemote.xcodeproj
```

- **Previews:** open `HomeView.swift` or `LiveView.swift` and show the canvas
  (Editor > Canvas). Each file has previews for landscape and upright, connected to the mock device.
- **Run on your iPhone/iPad:** pick your device as the run destination and press Run. Signing
  uses the same team and bundle ID as the Godot export (`com.gamemote.app`).

## Layout

| Folder | What |
|---|---|
| `ios/Gamemote/` | The app: SwiftUI screens, RealityKit controller, previews |
| `ios/GamemoteCore/` | Swift package: protocol v0, device link, mock device, console log (+ tests) |
| `protocol/` | GATT profile, frame format, routine bytecode, shared test vectors |
| `tools/` | Python reference implementation, BLE device simulator (`gm_sim.py`), CLI client (`gm_cli.py`) |
| `design/`, `production/` | Game brief, stories, reference images, screenshots |

## Tests

```bash
cd ios/GamemoteCore && swift test
```

```bash
python3 -m unittest discover -s tools/tests -t tools -p "test_*.py"
```

CI runs the Python tests on Linux, and on a macOS runner it runs `swift test` and builds the app
for the iOS Simulator.

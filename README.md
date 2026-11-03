# Gamemote

An iOS app built with Godot that remote-controls a BLE microcontroller, in two ways:

- **Live control** through a game-controller-style UI with bindable controls.
- **Routines** built in a Scratch-like block editor and run from the app.

Status: **planning the proof of concept.** See [`docs/POC_PLAN.md`](docs/POC_PLAN.md).

## Planned components

| Folder | What |
|---|---|
| `app/` | Godot 4.6.x project (GDScript) |
| `native/gamemote_ble/` | GDExtension (Objective-C++ / CoreBluetooth) for iOS and macOS |
| `firmware/` | ESP32-S3 firmware (PlatformIO + NimBLE-Arduino) |
| `protocol/` | GATT profile, frame format, shared test vectors |
| `tools/` | Python BLE reference client (`bleak`) and device simulator |

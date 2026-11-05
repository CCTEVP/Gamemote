# Gamemote

An iPhone/iPad app, built with Godot, that remote-controls a Bluetooth LE microcontroller:

- **Live control:** a game-controller-style UI bound to the device's channels and actions.
- **Routines:** sequences built in a Scratch-like block editor. They run either from the app
  (**Live**) or are uploaded to the board and keep running on their own (**Transferred**).

**Status:** proof of concept. The tracer bullet (connect, control, routines in both modes) is ready
for the first on-device test.

| Start here | |
|---|---|
| [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) | Build, export to Xcode, run on iPhone/iPad, test checklist |
| [docs/POC_PLAN.md](docs/POC_PLAN.md) | Plan, decisions, milestones, risks |
| [protocol/PROTOCOL.md](protocol/PROTOCOL.md) | BLE protocol v0: what makes a board "Gamemote-compatible" |
| [docs/diagrams/](docs/diagrams/) | Architecture map and expected-flow sequence (Archify HTML; open in a browser) |

## Layout

| Folder | What |
|---|---|
| `app/` | Godot 4.7 project (GDScript) |
| `native/gamemote_ble/` | GDExtension: CoreBluetooth backend for iOS/iPadOS/macOS |
| `protocol/` | GATT profile, frame format, routine bytecode, shared test vectors |
| `tools/` | Python reference implementation, BLE device simulator (`gm_sim.py`), CLI client (`gm_cli.py`) |

## Agent skills

`.claude/skills/` holds the [Scenario Godot expert skills](https://github.com/scenario-labs/skills/tree/main/skills/game-engines/godot), pinned to a reviewed commit in `skills-lock.json`. Claude Code loads them automatically in this repo. Update with `npx skills update -p`.

## Tests

```bash
python3 -m unittest discover -s tools/tests -t tools -p "test_*.py"
godot --headless --path app --import && godot --headless --path app -s res://tests/run_tests.gd
```

CI runs both on Linux, and compiles and link-checks the iOS/macOS extension on a macOS runner.

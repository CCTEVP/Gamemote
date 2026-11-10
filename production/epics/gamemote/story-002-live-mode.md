# Story 002: Live mode (the clay gamepad as its own screen)

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 2

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 2, Player goal & fail state):*

- [ ] Live mode shows the clay gamepad only: stick, four face buttons, STOP.
- [ ] The stick drives the device's first speed and first angle channels (value = neutral ± deflection × range, deadzone 0.12) and returns them to neutral on release.
- [ ] Face buttons come from the device's own description: the first action fires on press; a level channel is held while pressed; buttons with nothing to do are greyed.
- [ ] Stick and a button work at the same time with two fingers.
- [ ] STOP sets every channel to neutral and stops any running routine.
- [ ] Leaving Live mode, or the app going to the background, sends STOP (except while a Transferred routine runs); a lost link releases all controls.
- [ ] Presses give a haptic tap on iPhone and iPad.
- [ ] Round-trip time is shown in the console; against the Mac simulator, p95 ≤ 60 ms (PoC target).

*Layout and console (owner direction, 2026-11-10):*

- [ ] Upright (portrait): the controller sits at the bottom of the screen and a crystal console sits above it, shaped and lit like a clear piece of the controller.
- [ ] Sideways (landscape): the console becomes a small screen in the middle of the controller, between the stick and the buttons.
- [ ] The console shows useful plain-word lines: connection status (connecting, connected, reconnecting, lost), commands sent (stick values, button actions, STOP), feedback from the gadget (replies, telemetry, log), and errors.
- [ ] The console scrolls with the newest line last; repeated stick updates merge into one line instead of flooding it.
- [ ] Turning the device switches between the two layouts without dropping the connection or a held control.
- [ ] The app follows the device's orientation (upright and sideways); Home gets an upright layout with the two tiles stacked; the Routine builder stays locked to landscape until story 003 adds its upright layout.

---

## Implementation Notes

- Reuse `Gamepad3D` (`ui/table/gamepad_3d.gd`) and the bindings in `table.gd` (`_on_info`, `_on_stick`, `_on_button`); move them into the Live scene.
- Touch routing is per finger (touch index owns one control); keep that.
- Bindings by channel `kind` ("speed", "angle", "level") and action order; no layout editor (out of scope).
- Orientation: `window/handheld/orientation` goes from sensor landscape to sensor (all); the builder locks itself to landscape at runtime until story 003. Lay out from the viewport aspect on `size_changed`, not from the orientation setting.
- Console: a short ring buffer of lines fed by `Device` signals (state, log, telemetry, ACK, errors) and by the Live bindings; plain wording follows story 006.

---

## Out of Scope

- Story 001: Home and navigation. Story 004: Peek. Story 006: sizes and labels. Story 007: sounds.

---

## Files

- `src/ui/live/live_mode.gd`, `src/ui/live/live_mode.tscn` (new)
- `src/ui/table/gamepad_3d.gd`, `src/ui/table/table.gd` (bindings move out; upright/sideways layout)
- `src/ui/live/console.gd` (new: crystal console)
- `src/ui/home/home.gd` (upright layout), `src/project.godot` (orientation)
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `src/tests/run_tests.gd` cases (touch routing, bindings, STOP) OR a playtest doc; plus a retained screenshot of Live mode in `production/qa/evidence/` (anything visible needs one).

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/gamemote/story-001-home-and-connect.md`
- Unlocks: `story-004-peek.md`, `story-006-kid-friendly-basics.md`, `story-007-soft-sounds.md`

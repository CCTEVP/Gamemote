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
- [ ] Round-trip time is shown or logged; against the Mac simulator, p95 ≤ 60 ms (PoC target).

---

## Implementation Notes

- Reuse `Gamepad3D` (`ui/table/gamepad_3d.gd`) and the bindings in `table.gd` (`_on_info`, `_on_stick`, `_on_button`); move them into the Live scene.
- Touch routing is per finger (touch index owns one control); keep that.
- Bindings by channel `kind` ("speed", "angle", "level") and action order; no layout editor (out of scope).

---

## Out of Scope

- Story 001: Home and navigation. Story 004: Peek. Story 006: sizes and labels. Story 007: sounds.

---

## Files

- `src/ui/live/live_mode.gd`, `src/ui/live/live_mode.tscn` (new)
- `src/ui/table/gamepad_3d.gd`, `src/ui/table/table.gd` (bindings move out)
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

# Story 003: Routine builder

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 3

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 3, Player goal & fail state):*

- [ ] The builder shows a "When run" hat, a palette built from the device's channels and actions plus Wait and Repeat, and no gamepad.
- [ ] Dragging a palette tile near a slot snaps it in; dropped far from any slot it is discarded.
- [ ] Repeat wraps the blocks dropped inside it; dragging a block takes the blocks below it along.
- [ ] Tapping a block cycles its value (Wait 0.25/0.5/1/2 s, Repeat 2/3/5/10, Set min/neutral/max); dragging a block onto the palette deletes it.
- [ ] Run Live executes the routine from the app, the running block glows, and it stops if the link drops (device goes neutral).
- [ ] Transfer uploads the routine and it keeps running on the device after disconnect; Stop halts it; Transfer is disabled when the device cannot run routines.
- [ ] Errors from Run or Transfer (too large, device refused, upload failed) show in plain words in the status line.
- [ ] The chain compiles to the same bytecode the device accepts (`protocol/test_vectors.json` cases still pass).

*Owner direction, 2026-11-10:*

- [ ] The builder has an upright (portrait) layout as well as sideways, and drops the landscape lock story 002 put on it.
- [ ] `INTENT UNKNOWN — needs a design pass`: the routine-making UI, especially for Transferred routines, needs a better design than the current board. Start the story with a short design pass (`/ux-design` or `/quick-design`) and agree it with the owner before coding.

---

## Implementation Notes

- Reuse `BlockBoard` (`ui/table/block_board.gd`), `GmRoutine` and `Device.run_live` / `run_transferred`; move the board into its own scene.
- Keep it simple and visual (brief: ScratchJr-like, movement and timing only); no conditions, sensors or variables.

---

## Out of Scope

- Story 001: navigation. Story 004: Peek. Story 005: saving and the library. Story 006: icons and sizes. Story 007: sounds.

---

## Files

- `src/ui/builder/builder_mode.gd`, `src/ui/builder/builder_mode.tscn` (new)
- `src/ui/table/block_board.gd`, `src/ui/table/table.gd` (run wiring moves out)
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `src/tests/run_tests.gd` cases (snap, nesting, tap, delete, compile, run) must exist; plus a retained screenshot of the builder, empty and with a routine, in `production/qa/evidence/`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/gamemote/story-001-home-and-connect.md`
- Unlocks: `story-004-peek.md`, `story-005-saved-routines.md`, `story-006-kid-friendly-basics.md`, `story-007-soft-sounds.md`

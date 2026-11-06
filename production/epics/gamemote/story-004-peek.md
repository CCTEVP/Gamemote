# Story 004: Peek (drag empty space, spring back) in both modes

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: Visual/Feel
> **Estimate**: S
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 7

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 7):*

- [ ] In Live mode and in the Routine builder, dragging a finger that starts on empty table space turns and tilts the view (down to 28° above the table).
- [ ] On release the view springs back and settles exactly at the top-down resting angle (12° tilt).
- [ ] A touch that starts on a control or block never starts a peek, and peeking sends nothing to the device.
- [ ] The camera still fits the whole table on iPhone landscape and iPad after a peek.
- [ ] Stacked blocks and the pad's buttons are visibly readable from the side (screenshot shows depth).

---

## Implementation Notes

- The orbit already exists in `table.gd` (`_apply_camera`, spring back in `_process`, constants `ORBIT_*`). Move it into a camera helper used by both mode scenes so the behaviour is identical.
- Tuning is by feel on a device (turn 0.45°/pt, tilt 0.35°/pt); change only the constants.

---

## Out of Scope

- Story 002 / 003: the modes themselves.

---

## Files

- `src/ui/table/table_camera.gd` (new, extracted from `table.gd`)
- `src/ui/live/live_mode.gd`, `src/ui/builder/builder_mode.gd`
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot of a peek in each mode in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-004-peek-evidence.md`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-001-home-and-connect.md`, `story-002-live-mode.md`, `story-003-routine-builder.md`
- Unlocks: None

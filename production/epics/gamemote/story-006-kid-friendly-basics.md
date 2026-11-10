# Story 006: Kid-friendly basics

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: UI
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 6

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 6, "Who it's for": kids learning to program):*

- [ ] Every tappable thing (buttons, blocks, palette tiles, Home choices, library items) is at least 44 pt on screen on the smallest supported iPhone in landscape, measured, not assumed.
- [ ] Every block, gamepad button and Home choice has a picture plus a short word (at most two words); no label is text only.
  - Owner choice (2026-11-10): Live face buttons show letters (X/Y/A/B) like the reference controller, and their meaning is shown on the console screen; revisit with a real child before calling this done.
- [ ] STOP is visible and reachable with one tap at all times in Live mode and in the Routine builder.
- [ ] Messages (connection, errors, status) use plain words; no error codes or technical terms reach the screen.
- [ ] Nothing important is placed under the notch, home indicator or the thumb-covered corners of an iPhone in landscape (safe area checked).
- [ ] `INTENT UNKNOWN — inferred, not confirmed`: the icon set and the exact wording are undecided; the first pass uses simple clay-style icons and is reviewed with a real child before it is called done.

---

## Implementation Notes

- The 3D controls are measured through the camera (`table_to_screen`), so check the on-screen size, not the world size.
- `Label3D` text on blocks is the current label mechanism; add an icon beside it (a flat quad or `Sprite3D`).
- Rewrite status strings in `device_service.gd` and `table.gd` that expose terms like "ACK", "TRANSFER" or "BAD_PROGRAM" at the UI boundary only.

---

## Out of Scope

- A grown-up setting (speed limit, locked Transfer): open question in the brief.
- Story 007: sounds.

---

## Files

- `src/ui/table/gamepad_3d.gd`, `src/ui/table/block_board.gd`, `src/ui/home/home.gd`
- `src/core/device_service.gd` (UI-facing messages)
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: UI
**Required evidence**: a retained screenshot of each screen touched (Home, Live, builder, library), at iPhone and iPad sizes, with measured target sizes noted, in `production/qa/evidence/`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-002-live-mode.md`, `story-003-routine-builder.md`
- Unlocks: None

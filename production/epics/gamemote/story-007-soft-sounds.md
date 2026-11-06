# Story 007: Soft tactile sounds

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: Visual/Feel
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 5

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 5, art & audio direction: "gentle clicks and snaps"):*

- [ ] A soft click plays when a gamepad button or Home choice is pressed, and a gentle release sound when it is let go.
- [ ] A snap sound plays when a block snaps into the chain; a different soft sound plays when a block is deleted.
- [ ] Distinct start and stop sounds play when a routine runs and when it stops or finishes.
- [ ] STOP has its own clear but gentle sound.
- [ ] Each sound starts within one frame of the touch, so it feels attached to the press (checked by ear on a device).
- [ ] Sounds follow the device's volume and never play louder than a gentle level; many rapid presses don't pile up into noise.
- [ ] `INTENT UNKNOWN — inferred, not confirmed`: whether an in-app mute is needed, and where the sound files come from (recorded, generated or free library). Decide before implementing; note it in the story.

---

## Implementation Notes

- Use a small audio autoload with a few preloaded `AudioStreamPlayer`s (short one-shots) and a dedicated bus for UI sounds; `scenario-godot-audio` covers buses and variation.
- Add slight pitch variation per play so repeats don't sound mechanical.
- Sound files are assets under `src/assets/audio/`; keep them small (short WAV/OGG).

---

## Out of Scope

- Music and spoken voice (not in the brief).

---

## Files

- `src/core/sfx.gd` (new autoload), `src/assets/audio/*` (new)
- `src/ui/table/gamepad_3d.gd`, `src/ui/table/block_board.gd`, `src/ui/home/home.gd` (trigger points)
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot in `production/qa/evidence/` + sign-off (a device listening note) in `production/qa/evidence/story-007-soft-sounds-evidence.md`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-002-live-mode.md`, `story-003-routine-builder.md`
- Unlocks: None

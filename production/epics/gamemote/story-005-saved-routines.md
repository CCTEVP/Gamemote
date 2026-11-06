# Story 005: Saved routines library

> **Epic**: Gamemote
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: L
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: (set by /dev-story when implementation begins)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 4

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 4, core loop "Save the routine and pick it up next time"):*

- [ ] A routine can be saved with a name from the builder.
- [ ] A library lists the saved routines; opening one loads it into the builder exactly as saved.
- [ ] A routine can be renamed and deleted; delete asks for confirmation in plain words.
- [ ] Saved routines survive closing and reopening the app.
- [ ] Each saved routine records its format version, so older files stay readable when blocks are added later.
- [ ] A saved block that refers to a channel or action the connected device doesn't have is shown as unavailable and blocks Run/Transfer with a plain message instead of failing silently.
- [ ] A corrupt or unreadable file doesn't crash the app; it is skipped and the library says so.
- [ ] `INTENT UNKNOWN — inferred, not confirmed`: leaving the builder with unsaved changes keeps them as a draft instead of discarding them.

---

## Implementation Notes

- The model already exists: `BlockBoard.to_ast()` produces the routine AST (ids, ops, values). Store that as JSON under `user://routines/` with a `version` field; rebuild blocks from it on open (needs a `load_ast` on the board).
- Block ids are only meaningful inside one routine; regenerate on load.
- Keep it flat: no folders, tags, sharing or sync (out of scope).

---

## Out of Scope

- Cloud sync, sharing, accounts (brief out of scope). Story 006: picture-first labels for the library.

---

## Files

- `src/core/routine_store.gd` (new), `src/ui/builder/library.gd`, `src/ui/builder/library.tscn` (new)
- `src/ui/table/block_board.gd` (`load_ast`)
- `src/tests/run_tests.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `src/tests/run_tests.gd` cases (save/load round trip, rename, delete, corrupt file, missing channel) OR a playtest doc; plus a retained screenshot of the library in `production/qa/evidence/`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/gamemote/story-003-routine-builder.md`
- Unlocks: None

# Story 001: Home and connect, split the app into two modes

> **Epic**: Gamemote
> **Status**: In Progress
> **Layer**: Feature
> **Type**: UI
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-06

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 1

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7.2 | **Risk**: HIGH (Godot 4.7 is post-cutoff; see `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (MVP 1, Player goal & fail state):*

- [ ] The app opens on a Home screen, not the combined table prototype.
- [ ] Home shows the connection state (idle, scanning, connecting, connected, reconnecting) and one Connect/Disconnect control; Connect uses the first gadget found (existing behaviour).
- [ ] Once connected, Home offers two big choices: **Live** and **Routine builder**. Before connecting they are visible but disabled, with a plain reason shown.
- [ ] Choosing Live opens Live mode only (no blocks on screen); choosing Routine builder opens the builder only (no gamepad). Each mode has a Back control to Home that does not disconnect.
- [ ] If the link drops, Home and both modes show that the app is reconnecting, and it resumes by itself (existing auto-reconnect).
- [ ] The mock device stays selectable on desktop so the whole flow can be tried without a gadget.
- [ ] Layout fits iPhone landscape and iPad, respects the safe area, and is checked at both sizes.

---

## Implementation Notes

- Today `ui/table/table.tscn` holds the pad, the board and the top bar together; `table.gd` routes touches to both. Split it into a Home scene plus a scene per mode, sharing the existing `Device` autoload and the clay helpers (`ui/table/clay.gd`).
- Keep `DeviceService` unchanged; navigation is UI-only.
- The "Classic view" test screen (`ui/main.tscn`) can stay reachable from Home as a developer shortcut.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: the gamepad itself. Story 003: the builder itself. Story 004: Peek. Story 006: big-target and picture-first polish.

---

## Files

- `src/ui/home/home.gd`, `src/ui/home/home.tscn` (new: Home, connection, mode tiles)
- `src/ui/live/live_mode.gd`, `src/ui/live/live_mode.tscn` (new: Live mode, pad only)
- `src/ui/builder/builder_mode.gd`, `src/ui/builder/builder_mode.tscn` (new: Routine builder, board only)
- `src/ui/table/table.gd` (mode property, Back, framing per mode), `src/ui/table/clay.gd` (shared pill button)
- `src/ui/main.gd` (Classic view returns to Home), `src/project.godot` (main scene is Home)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: UI
**Required evidence**: a retained screenshot of Home (disconnected, connected) and each mode's entry, at iPhone and iPad sizes, in `production/qa/evidence/`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: `production/epics/gamemote/story-002-live-mode.md`, `story-003-routine-builder.md`, `story-004-peek.md`, `story-006-kid-friendly-basics.md`

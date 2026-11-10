<!-- STATUS -->
Epic:
Feature:
Task:
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-11-10
**Branch:** `claude/intelligent-planck-1tqhwt` (also pushed to `main`)
**Current task:** /story-done — production/epics/gamemote/story-001-home-and-connect.md: COMPLETE, closed
**Next step:** /dev-story production/epics/gamemote/story-002-live-mode.md
**Blocked on:** nothing
**Files in progress:** none
**Open questions:** none (tech debt logged: 0 items)
<!-- /CHECKPOINT -->

# Session state (checkpoint)

Read this first after a compaction, crash or `/clear`.

## Fixed product decisions (from the user)

- **Two separate app modes:** **Live** (game-controller UI, real-time control) and
  **Routine builder** (Scratch-like stacked blocks; run a routine Live or transfer it to the
  device). Separate screens/modes, not one combined view. The current `app/ui/table/` prototype
  shows the gamepad and the board side by side for testing only.
- 3D UI, top-down orthographic, soft clay/toy style; drag on empty space to peek, springs back.
- Routine run modes: Live (app runs it, stops on disconnect) and Transferred (runs on device).
- iPhone and iPad; hardware not chosen yet (Gamemote-compatible BLE device; `tools/gm_sim.py`).
- Rigor minimal, automation guided. Finished work is pushed to `main`.

## Current step

`/create-stories` done: `production/epics/gamemote/` holds EPIC.md and stories 001 to 007 (one per
brief MVP feature, in build order). Next: `/dev-story production/epics/gamemote/story-001-home-and-connect.md`
(split the table into Home, Live and Routine builder).

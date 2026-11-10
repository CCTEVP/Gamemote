<!-- STATUS -->
Epic:
Feature:
Task:
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-11-10
**Branch:** `claude/intelligent-planck-1tqhwt` (also pushed to `main`)
**Current task:** /dev-story — production/epics/gamemote/story-002-live-mode.md (Live mode)
**Next step:** /story-done production/epics/gamemote/story-002-live-mode.md
**Blocked on:** nothing
**Files in progress:** app/ui/live/console_log.gd, app/ui/live/console_view.gd, app/ui/table/gamepad_3d.gd, app/ui/table/table.gd, app/ui/table/clay.gd, app/ui/home/home.gd, app/core/device_service.gd, app/project.godot
**Run result:** OBSERVED — Live sideways (grey handheld, teal stick, X/Y/A/B, red STOP, console with status bar, log, legend) and upright (compact body, crystal block with console, STOP between stick and buttons), reconnecting line in the console, Home upright with stacked tiles and Home sideways unchanged; iPhone and iPad sizes in production/qa/evidence/story-002-live-mode/
**Open questions:** rotation switch while running, builder landscape lock, haptics and the 60 ms round-trip target need a device; upright body shows box seams; console status bar clips long gadget names
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

<!-- STATUS -->
Epic:
Feature:
Task:
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-11-06
**Branch:** `claude/intelligent-planck-1tqhwt` (also pushed to `main`)
**Current task:** /dev-story — production/epics/gamemote/story-001-home-and-connect.md (Home and connect, split the app into two modes)
**Next step:** /story-done production/epics/gamemote/story-001-home-and-connect.md
**Blocked on:** nothing
**Files in progress:** app/ui/home/home.gd, app/ui/home/home.tscn, app/ui/live/live_mode.gd, app/ui/live/live_mode.tscn, app/ui/builder/builder_mode.gd, app/ui/builder/builder_mode.tscn, app/ui/table/table.gd, app/ui/table/clay.gd, app/ui/main.gd, app/project.godot
**Run result:** OBSERVED — Home (disconnected: tiles greyed with "Connect your gadget first"; connected: Live and Routine builder tiles live), Live (pad only, Back), Builder (board only, Back), reconnecting shown on Home and Live; iPhone 1688x780 and iPad 2048x1536 in production/qa/evidence/story-001-home-and-connect/
**Open questions:** builder blocks look small on iPhone (story 006 target sizes); not yet tried on a real device
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

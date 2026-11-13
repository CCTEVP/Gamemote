<!-- STATUS -->
Epic:
Feature:
Task:
<!-- /STATUS -->

<!-- CHECKPOINT -->
**Updated:** 2026-11-13
**Branch:** `claude/intelligent-planck-1tqhwt` (also pushed to `main`)
**Current task:** native iOS trial (owner request): main is native SwiftUI + RealityKit; the Godot app is on the `Godot` branch
**Next step:** owner opens ios/Gamemote.xcodeproj on the Mac, checks the previews and the 3D look, runs on the iPhone; then decide: continue native (CoreBluetooth transport, then the routine builder) or go back to Godot
**Blocked on:** owner's look at the trial in Xcode
**Files in progress:** none
**Run result:** NOT VERIFIED — Swift cannot run in the cloud session; CI (Xcode 16.4) built the app and passed 18 core tests, but nobody has looked at the screens yet
**Open questions:** stories 001/002 were written for the Godot app; re-check them against the native app after the trial
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

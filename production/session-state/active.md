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

`/start`, `/project-stage-detect` and `/setup-engine godot 4.7` done: Godot 4.7.2, GDScript,
Mobile renderer, our own test runner, `src -> app` link (framework scans patched with `find -H`).
Next: `/adopt`, then `/reverse-document design app` to write `design/game-brief.md` with the
two modes above.

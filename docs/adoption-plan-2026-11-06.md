# Adoption Plan

> **Generated**: 2026-11-06
> **Project phase**: Concept (configured; minimal rigor does not advance it from source counts)
> **Engine**: Godot 4.7.2 (GDScript, Mobile renderer)
> **Template version**: v1.0+ (framework 1.2.0)

Work through these steps in order. Check off each item as you complete it.
Re-run `/adopt` anytime to check remaining gaps.

Audit scope at `workflow: minimal`: `design/game-brief.md`, the engine reference, project
config and the v1.0 migration check. GDDs, ADRs, UX specs, epics and sprints are not expected.

---

## Step 1: Fix Blocking Gaps

None.

---

## Step 2: Fix High-Priority Gaps

### 2a. Write the game brief
**Problem**: `design/game-brief.md` is missing. At minimal rigor it is the design record, and
`/create-stories` reads its MVP list.
**Fix**: `/reverse-document design app`. The app has 10+ source files, so the brief is written
from the built app. Tell it that the app has **two separate modes, Live (game controller) and
Routine builder**; the current table screen shows both side by side only as a prototype.
**Time**: 1 session
- [ ] design/game-brief.md written and reviewed

---

## Step 3: Bootstrap Infrastructure

Not on the minimal path: the brief's build order is the plan. Next: `/create-stories` (or
`/dev-story` once stories exist).

---

## Step 4: Medium and Low (advisory)

- [ ] **Performance budgets** unset (MEDIUM, deliberate). Set target frame rate and frame budget
  with `/settings` after profiling on an iPhone and an iPad.
- [ ] **Physics** unset (LOW, deliberate). No physics bodies are used; set it if that changes.
- [ ] **Forbidden patterns and allowed libraries** are empty by design (LOW). Fill in as
  decisions are made, in `.claude/docs/technical-preferences.md`.

---

## Notes

- **Coherence check false alarms.** `bash .claude/scripts/project-coherence.sh` reports that
  `export_presets.cfg` and `tests/run_tests.gd` are missing, and cannot find `project.godot`.
  It looks at the repo root and ignores `--path app`; all three exist in `app/`
  (`commands.test` passes 228 checks).
- **Code root.** `src` is a link to `app/`, and the framework scans use `find -H` to follow it
  (see `CLAUDE.md`).
- **Existing stories**: none exist yet; nothing to regenerate.

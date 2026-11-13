# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.7.2
- **Language**: GDScript
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

## Gamemote layout (read before writing code)

- **Native iOS app since 2026-11-13** (owner's decision): SwiftUI + RealityKit + CoreBluetooth,
  iOS 18. The Godot app is complete on the `Godot` branch; `main` is native.
- `ios/Gamemote.xcodeproj` + `ios/Gamemote/`: the app (SwiftUI screens with `#Preview`, the
  RealityKit clay controller). The project uses a synchronized folder: any Swift file added to
  `ios/Gamemote/` is in the target, no project edit needed.
- `ios/GamemoteCore/`: Swift package with everything that is not UI (protocol, device link,
  mock device, console log) and its XCTest tests against `protocol/test_vectors.json`.
- `protocol/`: BLE protocol v0 and test vectors; `tools/`: Python simulator (`gm_sim.py`) and CLI.
- Two separate app modes: **Live** (game controller) and **Routine builder**.
- Swift cannot be compiled in the cloud session (Linux, no toolchain). Verification is the CI
  job "GamemoteCore tests + app build (macOS)": push, then read its result with the GitHub
  tools. Screens are checked by the owner in Xcode previews or on the device.
- Tests: `cd ios/GamemoteCore && swift test` and
  `python -m unittest discover -s tools/tests -t tools -p "test_*.py"`. Finished work is pushed
  to `main` (owner's decision).
- Whenever the owner has to type something (a slash command, a terminal command, a value),
  give it in its own fenced code block so it can be copied (owner's rule, 2026-11-10).
- This repo installs the studio's agents and skills but not its `settings.json`: no hooks,
  no ask-first mode.
- Local patch to the vendored framework: every `find "$var"` in `.claude/scripts/` and
  `.claude/hooks/` uses `find -H` so scans follow the `src -> app` link. Re-apply after a
  framework upgrade (`sed -i 's/find "\$/find -H "$/g' .claude/scripts/*.sh .claude/hooks/*.sh`).
- Local patch, savings-first agent tiers (owner's choice, 2026-11-06): every agent in
  `.claude/agents/` sets `model:` and `effort:`, overriding `.claude/docs/model-tiers.md`.
  `opus`/medium: creative-director, technical-director. `sonnet`/high: engine-programmer,
  network-programmer, godot-gdextension-specialist. `sonnet`/low: qa-tester, writer,
  community-manager, producer. All others `sonnet`/medium. Re-apply after a framework upgrade.
  When starting an agent, keep its tier; pass a different `model` only when a task clearly
  outgrows it (e.g. a second failed attempt on the same task), and say so.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line below is engine-specific. /setup-engine
     rewrites it to @docs/engine-reference/<engine>/VERSION.md for the chosen
     engine, so a Unity or Unreal project stops loading the Godot reference every
     session. It defaults to Godot (the template's example engine); skills that
     need the pinned version read docs/engine-reference/<engine>/VERSION.md on
     demand regardless of this import. -->
@docs/engine-reference/godot/VERSION.md


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is not imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
  (exempt: `active.md` appends, agent memory, a subagent's new file at the path
  its orchestrating skill named; see `.claude/rules/agent-memory.md`)
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction
- A skipped or dismissed question is not an answer: act on nothing, re-ask in
  plain text and wait
- Started outside this file's folder? Warn first: hooks, deny rules and the
  ask-first mode load only when Claude Code starts here

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)

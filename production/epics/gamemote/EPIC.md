# Epic: Gamemote

> **Source**: `design/game-brief.md` (minimal tier: no GDDs, ADRs or architecture docs)
> **Status**: Ready

**Goal:** Drive a real gadget from your iPhone or iPad with a squishy clay gamepad, then teach
it tricks by snapping blocks into routines it can perform on its own.

**Scope (the brief's MVP):** Home and connect with two separate modes (Live, Routine builder),
Live gamepad, Routine builder, Peek, saved routines, kid-friendly basics, soft tactile sounds.

**Order (the brief's build order):** split the table prototype into Home, Live and Routine
builder first (stories 001 to 004), then saved routines (005), the kid-friendly pass (006),
sounds (007).

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Home and connect, split the app into two modes | UI | Ready | N/A |
| 002 | Live mode (the clay gamepad as its own screen) | Integration | Ready | N/A |
| 003 | Routine builder | Logic | Ready | N/A |
| 004 | Peek (drag empty space, spring back) in both modes | Visual/Feel | Ready | N/A |
| 005 | Saved routines library | Integration | Ready | N/A |
| 006 | Kid-friendly basics | UI | Ready | N/A |
| 007 | Soft tactile sounds | Visual/Feel | Ready | N/A |

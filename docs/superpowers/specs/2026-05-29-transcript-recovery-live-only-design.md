# Transcript recovery: only surface still-running sessions

**Date:** 2026-05-29
**Status:** Design — approved, pending spec review
**Scope:** Claude Code transcript discovery on app launch

## Problem

On launch the island shows a pile of `Unknown` session rows that the user
can't identify and can't jump to. Investigation traced them to one source:
**JSONL transcript discovery**.

There are two independent restore paths on launch:

1. **Registry restore** (`claudeSessionRegistry` → `claudeRecords`): sessions
   the app previously observed through hooks and persisted. These carry a real
   `terminalApp` and `terminalSessionID`, so they jump correctly.
2. **Transcript discovery** (`ClaudeTranscriptDiscovery.discoverRecentSessions`):
   sessions read directly from `~/.claude/projects/*.jsonl` that the app never
   saw through a hook. `ClaudeTranscriptDiscovery` hardcodes
   `terminalApp: "Unknown"` and leaves `terminalSessionID == nil`, because a
   transcript file has no terminal/IDE metadata.

Path 2 currently recovers **every** transcript modified within `maxAge`
(24h), including long-finished conversations. Each are created
`phase: .completed`, `attachmentState: .stale`, `origin: .live`, and (because
Claude sessions default to `isHookManaged == true`) stay permanently visible
via `isVisibleInIsland`'s `isHookManaged && !isSessionEnded` branch — even
after their process is gone. Restarting the app re-runs discovery and re-adds
them, so they accumulate.

These rows cannot jump: `AppModel.jumpToSession` guards out
`terminalApp == "unknown"`, so a tap sets `lastActionMessage` and returns with
no visible effect.

## Goals

- Stop surfacing finished/dead conversations recovered from transcripts.
- Keep the legitimate purpose of transcript discovery: surfacing a session that
  was **already running before the app launched** and that the bridge has not
  yet received a hook event for.
- Leave the registry-restore path and the live hook path unchanged — sessions
  that can jump keep working exactly as today.

## Non-goals

- Making `Unknown` sessions jumpable (recovering a missing `CMUX_SURFACE_ID`).
  Out of scope — the user chose to declutter at the source instead.
- Changing Codex / OpenCode / Cursor discovery.
- Touching the `maxAge` (24h) candidate window itself.

## Current behavior (reference)

- `SessionDiscoveryCoordinator.loadStartupDiscovery` calls
  `claudeTranscriptDiscovery.discoverRecentSessions()` **once at startup**
  (the only Claude transcript call site; the periodic re-scan at line ~401 is
  Codex-only). So pruned transcript sessions are not re-added later in the run.
- `applyStartupDiscoveryPayload` merges them into state via
  `mergeDiscoveredSessions`.
- `ProcessMonitoringCoordinator` reconcile then runs `markProcessLiveness`
  (sets `isProcessAlive`) and `removeInvisibleSessions`.

## Design

Treat transcript-discovered sessions as **provisional** until something
confirms they are real and current. Drop the ones that are never confirmed.

1. **Mark on discovery.** Tag each session produced by
   `ClaudeTranscriptDiscovery` as provisional (a transient flag on
   `AgentSession`, e.g. `isProvisionalDiscovery`, default `false`, not relied
   upon by registry restore). Registry-restored and hook-created sessions are
   never marked.

2. **Confirm.** A provisional session becomes confirmed (flag cleared) when
   either:
   - the process-monitoring reconcile finds a matching live process
     (`isProcessAlive` set true), or
   - a hook event arrives for that session id (the bridge upserts it as a real
     session).

3. **Prune.** After the **first full process-monitoring reconcile** following
   startup discovery, remove every session that is still
   `isProvisionalDiscovery == true && !isProcessAlive`. Because Claude
   transcript discovery does not re-run during the session, pruned sessions
   stay gone unless a later hook event re-surfaces them (self-correcting).

### Net effect

- Dead historical conversations are dropped → the `Unknown` graveyard clears.
- A session that was genuinely running before launch is kept (matched to its
  live process), and self-heals to its real terminal (`cmux` + surface id) on
  its next hook event.
- A false-negative match (alive session wrongly unmatched) is self-correcting:
  its next hook event re-creates it as a real, jumpable session.

## Affected components

- `Sources/OpenIslandCore/AgentSession.swift` — add the transient
  `isProvisionalDiscovery` flag (Sendable/Codable-compatible; excluded from or
  harmless to persistence).
- `Sources/OpenIslandCore/ClaudeTranscriptDiscovery.swift` — set the flag on
  produced sessions.
- `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift` — clear the flag
  when a live process confirms a session; run the one-shot prune of
  unconfirmed provisional sessions after the first post-startup reconcile.
- Hook ingestion (`BridgeServer` / `SessionState.apply`) — ensure a hook event
  for a provisional session clears the flag (it is now a confirmed session).
- `mergeDiscoveredSessions` / visibility — verify a provisional, not-yet-alive
  session does not get permanently pinned by the `isHookManaged` visibility
  branch before the prune runs (acceptable to show briefly, then prune).

## Edge cases

- **Provisional session that is alive but unmatched by the predicate:** pruned,
  then re-surfaced by its next hook event. Acceptable.
- **App relaunch:** discovery re-runs, re-marks provisional, re-confirms/prunes.
  Steady state shows only running sessions.
- **Registry + transcript collision** (same session in both): the merge keeps
  the registry version (real terminal info); not marked provisional.

## Testing

- Unit: a `ClaudeTranscriptDiscovery` output session carries the provisional
  flag.
- Unit/reducer: prune removes `provisional && !isProcessAlive`; keeps
  `provisional && isProcessAlive`; never touches non-provisional sessions.
- Unit: a hook event for a provisional session clears the flag so it survives
  the prune.
- `swift build` + `swift test`.
- Manual: launch with stale finished transcripts present → no `Unknown` rows;
  launch with a Claude session actively running in cmux that the app didn't
  start → it appears and jumps after its next event.

## Out of scope / follow-ups

- Backfilling `CMUX_SURFACE_ID` for live `Unknown` sessions (separate idea).
- A proper pressed-state row style (separate UX request).

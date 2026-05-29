# Transcript recovery: only surface still-running sessions

**Date:** 2026-05-29
**Status:** Design — revised after code review, pending re-review
**Scope:** Claude Code transcript discovery on app launch

## Problem

On launch the island shows a pile of `Unknown` session rows the user can't
identify and can't jump to. Source: **JSONL transcript discovery**.

Two independent restore paths run on launch:

1. **Registry restore** (`claudeSessionRegistry` → `claudeRecords`): sessions
   the app persisted from prior runs. *Intended* to carry real terminal info —
   but see the pollution note below, this is not guaranteed.
2. **Transcript discovery** (`ClaudeTranscriptDiscovery.discoverRecentSessions`,
   `SessionDiscoveryCoordinator.swift:99`, **startup only**): sessions read
   directly from `~/.claude/projects/*.jsonl`. It hardcodes
   `terminalApp: "Unknown"`, `terminalSessionID == nil`, `origin: .live`,
   `attachmentState: .stale`, `phase: .completed`
   (`ClaudeTranscriptDiscovery.swift:197-213`). A transcript has no terminal
   metadata.

These rows cannot jump: `AppModel.jumpToSession` guards out
`terminalApp.lowercased() == "unknown"` (`AppModel.swift:1310`).

### Actual mechanism (corrected after review)

The earlier draft wrongly attributed permanent visibility to an
`isHookManaged && !isSessionEnded` branch. That is incorrect:

- `isHookManaged` defaults `false` (`AgentSession.swift:383`) and is only set
  `true` inside `SessionState.apply(.sessionStarted)` (`SessionState.swift:78`).
  Transcript sessions are injected via `mergeDiscoveredSessions`
  (`SessionDiscoveryCoordinator.swift:171-198`) using the default init — they
  **never** go through `apply`, so `isHookManaged == false`.
- For such a session `isVisibleInIsland` (`AgentSession.swift:525-535`) falls to
  the `if isProcessAlive { return true }` branch — visibility is governed by
  `isProcessAlive`, not hook state.

The real reasons the Unknown rows appear and recur:

1. **Re-discovered every launch.** Transcript discovery re-scans the last 24h
   (`maxAge`) of `.jsonl` files on every startup, so finished conversations are
   re-added each run. The recurrence is disk re-scan, not state accumulation.
2. **Two-strike grace shows them for one reconcile round.** A discovered
   session starts `isProcessAlive == false`. The reconcile's grace logic
   (`SessionState.swift:408-416`) sets `processNotSeenCount 0→1` and
   `isProcessAlive = (1 < 2) == true` on the **first** reconcile when no process
   matches — so it becomes visible for one round, then on the second reconcile
   (`count >= 2 → isProcessAlive = false`) `removeInvisibleSessions` drops it.

So today's symptom is a burst of `Unknown` rows that lingers ~1 reconcile cycle
per launch (annoying with many recent transcripts), not permanent residency.
The goal stands; the mechanism description must be accurate so the fix targets
the real cause.

### Persistence pollution (was missing from the draft)

`applyStartupDiscoveryPayload` calls `scheduleClaudeSessionPersistence()` right
after merging discovered sessions (`SessionDiscoveryCoordinator.swift:174`). Its
filter keeps any session with `jumpTarget != nil || claudeMetadata?.transcriptPath != nil`
(`:489`) — a discovered `Unknown` session has **both**, so it is written to the
Claude registry. Because `shouldRestoreToLiveState == (origin != .demo)`
(`ClaudeSessionRegistry.swift:120`) and transcript `origin == .live`, it is then
restored next launch via **Path 1** with its `Unknown` jumpTarget intact
(`restorableSession` only forces `attachmentState = .stale`). The two paths are
therefore **not** independent, and Path 1 is **not** guaranteed to hold
jumpable sessions.

(The current code partially self-cleans: the second reconcile removes the dead
session and `onPersistenceNeeded` re-saves the registry without it. The fix must
preserve this self-cleaning rather than depend on a new prune step.)

## Goals

- Stop surfacing finished/dead conversations recovered from transcripts —
  ideally **zero rounds** of visible `Unknown`, not "eventually disappears".
- Keep transcript discovery's real purpose: surfacing a session **already
  running before launch** that the bridge hasn't received a hook event for yet.
- Do not write un-jumpable `Unknown` sessions to the registry.
- Leave the live hook path unchanged; jumpable sessions keep working.

## Non-goals

- Making `Unknown` sessions jumpable (recovering a missing `CMUX_SURFACE_ID`).
- Changing Codex / OpenCode / Cursor discovery.
- Changing the 24h `maxAge` candidate window itself.

## Design — intersect discovery output with live processes

Instead of adding everything then pruning (which fights the two-strike grace and
the persistence timing), **filter at the discovery stage so only sessions backed
by a live agent process are produced.** This is the literal meaning of the title.

1. **Gather live processes during startup discovery.** In
   `loadStartupDiscovery` (already on a background thread,
   `SessionDiscoveryCoordinator.swift`), run the existing
   `ActiveAgentProcessDiscovery().discover()` once.

2. **Keep only matched candidates.** For each `ClaudeTranscriptDiscovery`
   candidate, keep it only if it matches a live Claude process. Reuse the
   existing matching used by `ProcessMonitoringCoordinator.sessionIDsWithAliveProcesses`
   (`:265`): primarily **transcriptPath equality** (`process.transcriptPath ==
   candidate.claudeMetadata?.transcriptPath`, `:304-307`), with the TTY+CWD
   fallback (`:313+`). Extract this match as a pure helper so both call sites
   share it. Unmatched candidates are **dropped before** they enter state or the
   persistence payload.

3. **Nothing else changes.** Registry restore, the reconcile/two-strike logic,
   `removeInvisibleSessions`, and the hook path are untouched. Matched
   pre-launch sessions self-heal to their real terminal (`cmux` + surface id) on
   their next hook event. A false-negative match (alive but unmatched) is
   self-correcting: its next hook event creates it as a real, jumpable session.

### Net effect

- Dead historical conversations never enter state → **no flash, no Unknown
  graveyard** (resolves problems 1 and 2 — no reliance on the prune predicate).
- Unmatched sessions are never persisted → **no new registry pollution**
  (resolves problem 3).
- Pre-existing registry pollution (from before this fix) self-cleans within one
  run: those entries restore, fail to match a live process, and are removed by
  the existing two-strike + `removeInvisibleSessions`, then re-saved out by
  `onPersistenceNeeded`. No separate migration step is required, but this
  reliance is now explicit.

## Affected components

- `Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift` — run process
  discovery in `loadStartupDiscovery`; intersect Claude transcript candidates
  against live processes before building `discoveredClaudeSessions`; ensure
  unmatched candidates are excluded from `scheduleClaudeSessionPersistence`.
- `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift` — extract the
  Claude live-process match (transcriptPath / TTY+CWD) from
  `sessionIDsWithAliveProcesses` into a reusable pure helper.
- `Sources/OpenIslandCore/ClaudeTranscriptDiscovery.swift` — no behavior change
  required if matching happens in the coordinator; revisit only if the helper
  needs to live closer to discovery.
- No `AgentSession` field change is needed (the provisional flag is dropped).

## Edge cases

- **Pre-launch running session whose process snapshot lacks transcriptPath:**
  falls back to TTY+CWD match; if still unmatched it is dropped and re-surfaced
  by its next hook event. Acceptable.
- **App relaunch:** discovery + intersection re-runs; steady state shows only
  running sessions.
- **Pre-existing registry pollution:** self-cleans within one run (see above).
- **`firstSeenAt` ordering:** dropped candidates never set `firstSeenAt`
  (`AgentSession.swift:366-367`), so they no longer perturb the closed-island
  right-slot grid order — a side benefit of dropping pre-state.

## Testing

- End-to-end (the key one): launch with a finished transcript < 24h old and **no
  matching live process** → the `Unknown` row appears in **zero** reconcile
  rounds (assert it never enters `state.sessions`, not merely "is removed
  later").
- End-to-end: launch with a Claude session actively running in cmux that the app
  didn't start (live process present, matching transcriptPath) → it is surfaced,
  and jumps after its next hook event.
- Unit: the extracted match helper returns true for transcriptPath equality,
  true for TTY+CWD match, false otherwise.
- Unit: an unmatched discovered candidate is excluded from the persistence
  payload (no registry write).
- `swift build` + `swift test`.

## Out of scope / follow-ups

- Backfilling `CMUX_SURFACE_ID` for live `Unknown` sessions (separate idea).
- A proper pressed-state row style (separate UX request).

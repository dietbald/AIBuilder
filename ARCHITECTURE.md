# AIBuilder Architecture

This document describes how AIBuilder works internally — the agent model, data flow, session design, and the reasoning behind each major design decision.

---

## The Big Picture

AIBuilder is a multi-agent autonomous development system. A single human input (`FEATURES.md`) drives a pipeline of specialized AI agents that produce production-ready, tested, staged software without human involvement — except when the system genuinely cannot proceed.

```
Human input
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  INCEPTION PHASE  (one-time, TJ participates)        │
│  BA → TechStack → Brand → Domain → Infra → Scaffold  │
│  Output: FEATURES.md, AGENTS.md, CODING_STANDARDS.md │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  DEVELOPMENT LOOP  (runs autonomously)               │
│                                                      │
│  ┌─────────────┐   3 min tick   ┌────────────────┐  │
│  │  cron job   │ ─────────────► │   Conductor    │  │
│  └─────────────┘                │  (persistent)  │  │
│                                 └───────┬────────┘  │
│  ┌─────────────┐   15 min audit         │ dispatch  │
│  │  cron job   │ ──────────────►  Co-   │           │
│  │             │                Conductor│           │
│  └─────────────┘                        ▼           │
│                              ┌────────────────────┐ │
│                              │   Sub-agents        │ │
│                              │  (one-shot, own     │ │
│                              │   tmux session)     │ │
│                              └────────────────────┘ │
└─────────────────────────────────────────────────────┘
    │
    ▼
Staging deploy + Telegram notification to TJ
```

---

## Layer 1 — The Conductor

The Conductor is the brain of the development loop. It is a **persistent interactive Claude CLI session** running in its own tmux session (`conductor-<PROJECT>`). It never exits between ticks.

### What it does on each tick

A cron job fires `tmux send-keys -t conductor-<PROJECT> "tick" Enter` every 3 minutes. On receiving "tick", the Conductor:

1. Increments the tick counter (session rotation at tick 50)
2. Re-reads `STATUS.md` — the authoritative pipeline state
3. Runs the timeout watchdog — kills agents stuck >30 min
4. Polls agent output files for `---DEVLOOP_DONE---`
5. Processes completions — advances features in STATUS.md
6. Takes exactly **one** action (dispatch, resolve blocker, or log idle)
7. Updates STATUS.md atomically
8. Logs one line to `conductor-log.md`

**One action per tick is a hard rule.** This is intentional — it keeps the Conductor's reasoning simple and auditable. A Conductor that does five things per tick is hard to debug when one of them fails.

### Why persistent session, not one-shot

The early design used `claude --print` (one-shot, exits after one response). This was fatally wrong — the Conductor had no way to know what it had already dispatched without re-reading all state from scratch on every tick, and had no conversation history to reason across ticks.

The persistent session means the Conductor remembers what it dispatched two ticks ago without re-reading every output file. STATUS.md remains the authoritative truth source, but conversation history provides context that would otherwise require expensive re-reads every 3 minutes.

### Context rot mitigation

Persistent conversation history is a liability over time. After ~50 ticks, accumulated context degrades reasoning quality — the Conductor begins weighting stale conversation history over fresh STATUS.md reads. At tick 50:

1. The Conductor resets the tick counter to 0
2. Schedules `tmux kill-session` with a 5-second delay
3. The Co-Conductor sees the dead session and restarts it (Level 3 action)
4. The restarted Conductor re-orients from STATUS.md — no state is lost, only conversation history

All durable state lives in files, not in conversation history. Rotation clears the rot without losing anything real.

---

## Layer 2 — The Co-Conductor

The Co-Conductor is a second persistent interactive Claude CLI session (`coconductor-<PROJECT>`). It is the **supervisor** — it watches the Conductor, not features.

A cron job fires an `audit` message every 15 minutes. Before sending, cron saves a STATUS.md snapshot to `.devloop/status-snapshot.md`. The Co-Conductor then:

1. Compares current STATUS.md to the 15-minute-old snapshot (did anything move?)
2. Checks whether the Conductor session is alive
3. Checks whether active agent sessions exist
4. Takes **exactly one corrective action** if needed, then stops

### Corrective action levels

| Level | Condition | Action |
|---|---|---|
| 0 | All clear | Log only. No Telegram. |
| 1 | No progress, no agents running | Send wake-up message to Conductor |
| 2 | STATUS.md features don't match FEATURES.md | Send realignment message to Conductor |
| 3 | Conductor session is dead | Kill, recreate, restart Claude, send STATUS.md context |
| 4 | Restart failed — Conductor dead again on next audit | Write alert file, Telegram TJ, stop |

The Co-Conductor dispatches only the Conductor agent itself (on Level 3 restart) — never any development agents (spec-author, implementer, etc.). Its only job is keeping the Conductor alive and on track.

**Terminology note:** Co-Conductor uses "Level 0–4" for its corrective action scale. The Conductor uses "Tier 1–4" for escalation severity. These are distinct numbering systems. Co-Conductor Level 4 = "Conductor cannot be auto-recovered." Conductor Tier 4 = "business/credential decision requiring human judgment." Do not conflate them.

---

## Layer 3 — Sub-Agents

Sub-agents are **one-shot** `claude --print --agent` processes. Each runs in its own dedicated tmux session. They start, do their work, write output, and exit. The Conductor polls for their completion.

```
Session name:  agent-<ROLE>-<FEATURE>-<PROJECT>
Output file:   /tmp/devloop-out-<ROLE>-<FEATURE>.txt
Dispatch time: .devloop/agent-dispatch/<ROLE>-<FEATURE>.time
```

One session per sub-agent, one window per session — never a sub-agent as a window inside another session. This keeps sessions independently addressable and independently killable.

### Why one-shot for sub-agents but persistent for the Conductor

Sub-agents do a bounded task: write this spec, implement this feature, review this diff. A one-shot process is the right primitive — it starts, does its work, and exits cleanly. The output file is the artifact. There is no benefit to persistence.

The Conductor, by contrast, orchestrates across an unbounded number of ticks. It needs to reason across time ("I dispatched F-03 two ticks ago, has it finished?"). A persistent session with conversation history gives it that continuity cheaply.

---

## The Feature Pipeline

Every feature in `FEATURES.md` moves through these stages in order:

```
pending
  │
  ▼
speccing ──────────────────► spec-verifying ──► spec-approved
  │  (Spec Author)              (Spec Verifier)        │
  │  FAIL→retry (max 2)         FAIL→retry (max 2)     │
  │                                                    ▼
  │                                              implementing
  │                                              (Implementer — Sonnet)
  │                                              FAIL→retry
  │                                                    │
  │                                                    ▼
  │                                            test-authoring
  │                                            (Test Author — Sonnet)
  │                                            e2e tests from spec
  │                                            FAIL→retry
  │                                                    │
  │                                                    ▼
  │                                              reviewing
  │                                              (Reviewer — Opus ✱)
  │                                              FAIL→review-failed
  │                                                    │
  │                                            review-failed
  │                                            →re-implement (next tick)
  │                                                    │
  │                                                    ▼
  │                                              qa-testing
  │                                              (QA Tester — Opus)
  │                                              FAIL→re-implement
  │                                                    │
  │                                                    ▼
  │                                               done
  │                                                    │
  │                                          (Conductor dispatches Deployer)
  │                                                    ▼
  │                                             deploying
  │                                             (Deployer — Opus)
  │                                             FAIL→retry
  │                                                    │
  │                                                    ▼
  │                                              staged ◄── Deployer PASS
  │                                                    │
  │                                       (all features staged)
  │                                                    ▼
  │                                          COMPLETION.md written
  │                                          cron stopped
  │                                          sessions self-terminate
  ▼
blocked-tier4 (human required)
```

✱ Cross-model verification: Implementer and Test Author run on Claude Sonnet. Reviewer runs on Claude Opus. Different model families catch each other's systematic blind spots.

### Retry logic

Every FAIL verdict increments a counter in `RETRIES.md` (key: `FEATURE:ROLE`). At `MAX_RETRIES=2`, the Conductor escalates to Tier 4 instead of re-dispatching. This prevents infinite loops burning tokens on a genuinely broken feature.

Timeouts (agent running >30 min with no output) are treated as FAIL and consume from the same retry budget.

---

## The Firewall — Upstream vs Downstream

The pipeline is split into two zones with an explicit firewall:

```
UPSTREAM                    FIREWALL                  DOWNSTREAM
────────────────────────────────────────────────────────────────
FEATURES.md                                           spec.md
domain.md            ════════════════════►            (only this)
brand.md
techstack.md

Spec Author
Spec Verifier
                                                  Implementer
                                                  Test Author
                                                  Reviewer
                                                  QA Tester
```

**The Implementer never reads `FEATURES.md`.** Its only input is `spec.md`. This is intentional:

1. It forces the spec to be complete. If the Implementer had access to FEATURES.md, it could paper over spec gaps by guessing intent — producing code that maybe-works but isn't testable against the spec.
2. It makes implementation decisions independent of product decisions. The Implementer decides HOW; the Spec Author decided WHAT.
3. It makes the Reviewer's job tractable. The Reviewer only needs to compare `spec.md` to the diff — not infer intent from FEATURES.md.

---

## STATUS.md — The Single Source of Truth

STATUS.md is the pipeline's durable state. Every agent reads it. **The Conductor is the sole writer.** Sub-agents never write to STATUS.md — they write only to their designated output files. The Conductor reads the output verdict and performs all state transitions atomically.

```markdown
| Feature | Status |
|---|---|
| F-01-user-auth | done |
| F-02-bid-submission | reviewing |
| F-03-search | speccing |
| F-04-notifications | pending |
```

### Why files, not conversation history

Conversation history is ephemeral — it lives in a Claude session that can die, be rotated, or be restarted. STATUS.md survives all of these events. When the Conductor restarts after session rotation, it re-reads STATUS.md and immediately knows exactly where every feature is. No reconciliation needed.

This is the key architectural property: **all durable state lives in files, never in Claude's memory.**

---

## AGENT_SCHEMA.md — The Output Contract

Every sub-agent ends its output with a structured block:

```
---AGENT_OUTPUT---
verdict: PASS | FAIL
status: done | blocked
output_path: <path to primary artifact>
blocking_count: <integer>
notes: <required on FAIL — actionable description>
---DEVLOOP_DONE---
```

The `---DEVLOOP_DONE---` sentinel is what the Conductor polls for. Before reading the schema block, the Conductor verifies that `---AGENT_OUTPUT---` appears before `---DEVLOOP_DONE---` — catching partial writes from agents that crashed mid-output.

This contract is what makes the pipeline machine-readable. The Conductor doesn't parse natural language — it reads a structured block and acts on `verdict`.

---

## Double-Dispatch Prevention

Before dispatching any sub-agent, the Conductor checks whether its session already exists:

```bash
tmux has-session -t "=agent-${ROLE}-${FEATURE}-${PROJECT_NAME}" 2>/dev/null
```

The `=` prefix forces exact-match (tmux 3.x+). Without it, a session named `agent-dev-spec-author-F-01-BidPlatform` would match a partial check for `agent-dev-spec-author-F-01`, creating false positives.

If the session exists, the Conductor skips dispatch. This prevents the same feature from being worked on twice simultaneously if the Conductor processes a stale tick or if tick stacking occurs.

---

## The Cron Trigger Mechanism

The Conductor and Co-Conductor are triggered by cron via `tmux send-keys`:

```
*/3  * * * *  tmux send-keys -t 'conductor-<PROJECT>' 'tick' Enter  # devloop-<PROJECT>-tick
*/15 * * * *  cp STATUS.md .devloop/status-snapshot.md; tmux send-keys -t 'coconductor-<PROJECT>' 'audit' Enter  # devloop-<PROJECT>-audit
```

This is an undocumented assumption: that `claude` interactive mode accepts input injected via tmux pseudo-TTY the same way it accepts input from a real terminal. **ST-01 (the PONG test) verifies this assumption before any real project runs.**

If the PONG test fails, the trigger mechanism must be replaced with a file-based queue (Conductor polls a trigger file) or named pipe.

### Tick stacking risk

If the Conductor is mid-response when cron fires, tmux buffers "tick" and delivers it after the response completes. On a 3-minute cron interval with a slow dispatch, two ticks can queue. The Conductor's one-action-per-tick rule limits the blast radius — it processes one queued tick at a time.

A lockfile mechanism (write at tick start, delete at tick end; skip if lockfile exists) would prevent this entirely but is not yet implemented.

---

## The Timeout Watchdog

On every tick, the Conductor checks `.devloop/agent-dispatch/*.time` files. Each file records the Unix timestamp when an agent was dispatched. If:

- The dispatch file exists (agent was launched)
- The output file does NOT contain `---DEVLOOP_DONE---` (not finished)
- `now - dispatch_time > 1800` (30 minutes have elapsed)

Then the Conductor kills the session, removes the dispatch record, and applies the standard retry logic. The timeout counts against the retry budget — an agent that times out twice hits the same Tier 4 ceiling as one that FAILs twice.

This prevents a stuck agent from silently consuming tokens indefinitely with no output.

---

## Cross-Model Verification

The Conductor selects models by role at dispatch time:

```bash
case "$ROLE" in
  dev-implementer|dev-test-author) AGENT_MODEL="claude-sonnet-4-6" ;;
  *) AGENT_MODEL="claude-opus-4-7" ;;
esac
```

Implementer and Test Author run on **Claude Sonnet 4.6**. Reviewer runs on **Claude Opus 4.7**. All other agents (Spec Author, Spec Verifier, QA Tester, Auditor, Deployer) default to Opus 4.7.

The reason: two agents from the same model family trained on the same data will make the same mistakes and share the same blind spots. A Reviewer on a different model than the Implementer catches systematic biases that a same-model review normalises — the same way a second human with different training catches errors the first human's mental model accepts as normal.

## Structured Event Log

Every significant state transition is written to `05-progress/devloop-event.log` by the Conductor:

```
2026-05-04T12:00:00Z | feature=F-01 | role=dev-spec-author | action=dispatched | session=agent-dev-spec-author-F-01-BidPlatform model=claude-opus-4-7
2026-05-04T12:04:30Z | feature=F-01 | role=dev-spec-author | action=completed  | verdict=PASS blocking=0
2026-05-04T12:05:00Z | feature=F-01 | role=dev-implementer | action=dispatched | session=agent-dev-implementer-F-01-BidPlatform model=claude-sonnet-4-6
```

This is the system's flight recorder. When the system fails silently — which autonomous systems inevitably do — the event log is the primary diagnostic artifact. STATUS.md records final state; the event log records the path that got there.

---

## Escalation Tiers

| Tier | Who resolves | Examples |
|---|---|---|
| 1 | Conductor directly | TypeScript error, missing import, test config |
| 2 | Conductor + DECISIONS.md | Spec ambiguity with clear intent |
| 3 | Conductor dispatches Auditor | Cross-feature conflict |
| 4 | TJ (human) | Business decision, expired API key, retry ceiling exceeded, git auth |

Tier 1–3 resolutions are documented in `DECISIONS.md`. Tier 4 fires a Telegram alert and blocks that feature lane — other features continue in parallel if possible.

---

## Session Naming Convention

| Component | Session name |
|---|---|
| Conductor | `conductor-<PROJECT_NAME>` |
| Co-Conductor | `coconductor-<PROJECT_NAME>` |
| Sub-agent | `agent-<ROLE>-<FEATURE>-<PROJECT_NAME>` |

`PROJECT_NAME` is `basename` of the project directory (e.g., `BidPlatform`). All names are unique per project, so multiple projects can run simultaneously on the same machine without collision.

---

## Pipeline Termination

When all features in STATUS.md reach `staged` status (deployed to staging), the Conductor:

1. Writes `COMPLETION.md` with timestamp and feature count
2. Removes all cron jobs for this project
3. Sends a Telegram notification to TJ
4. Self-terminates both conductor and co-conductor sessions after 5 seconds

Note: `done` is the intermediate state (QA passed); `staged` is the true terminal state (deployed to staging). The Co-Conductor checks for `COMPLETION.md` before doing a Level 3 restart — if it exists, the pipeline completed intentionally and the conductor should not be restarted.

This is the only way the pipeline stops autonomously. Any other stop (mid-project) must be done manually via `devloop-stop.sh`.

---

## Known Limitations

**tmux `send-keys` payload size.** Shell argument quoting and tmux's internal line-length limits can silently truncate long agent prompt injections. This is a structural constraint of using `tmux send-keys` as the trigger mechanism. Keep `tick` and `audit` messages short — they are triggers, not full prompts. Agent context is built from files, not from the trigger string.

**tmux server restart / OS reboot.** If the tmux server itself is killed (e.g., system reboot), all sessions are lost. STATUS.md, RETRIES.md, and agent output files survive (they are on disk). Recovery: run `devloop-start.sh` again — the Conductor re-reads STATUS.md and resumes from the current pipeline state. Any agent that was mid-execution when tmux died will be re-dispatched on the next tick.

**14-minute dead window after session rotation.** When the Conductor self-terminates at tick 50, the Co-Conductor may take up to 14 minutes to detect the dead session and restart it (audit interval is 15 minutes). No state is lost during this window, but the pipeline does not advance. This is an accepted trade-off of the 15-minute audit interval.

**Tick stacking.** If the Conductor is processing a slow tick when cron fires again, tmux buffers the second `tick`. The Conductor processes it immediately after the first completes. The one-action-per-tick rule limits blast radius but does not prevent stacking entirely. A lockfile mechanism would eliminate this but is not yet implemented.

---

## Key Design Properties

| Property | Mechanism |
|---|---|
| All durable state in files | STATUS.md, RETRIES.md, DECISIONS.md, agent output files |
| Conductor is sole STATUS.md writer | Sub-agents write only output files; Conductor owns all state transitions |
| Agents are independently restartable | One-shot sub-agents; Conductor re-orients from STATUS.md |
| No double-dispatch | `tmux has-session -t "=name"` exact-match check before every dispatch |
| No silent runaway agents | Timeout watchdog kills at 30 min; $MAX_RETRIES=2 caps retries |
| Context rot prevented | Session rotation at tick 50 |
| Human only for genuine blockers | Tier 4 escalation with Telegram |
| Pipeline is machine-readable | AGENT_SCHEMA.md structured 5-field output contract |
| Spec is the contract | Firewall isolates upstream and downstream agents |
| Cross-model verification | Implementer/Test Author on Sonnet; Reviewer on Opus |
| Clean termination | Completion detected, cron stopped, Telegram sent, sessions self-terminate |

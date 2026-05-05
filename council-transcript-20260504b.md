# AIBuilder Council Transcript — Redesigned Architecture
**Date:** 2026-05-04 (Council #2)
**Previous council:** council-transcript-20260504.md

---

## Framed Question

TJ has redesigned AIBuilder — an autonomous software development system. The previous design (counciled earlier today) had fatal bugs: the conductor ran via `claude --print` (one-shot, no loop), tmux session names mismatched, no inception gate, and double-dispatch on re-entry.

The redesigned architecture:

1. **Conductor** runs as a persistent interactive `claude --agent conductor.md` session inside its own tmux session named `conductor-${PROJECT_NAME}` (one window only). A cron job sends the string "tick" to it via `tmux send-keys` every 3 minutes.
2. **Co-conductor** runs as a persistent interactive `claude --agent co-conductor.md` session inside its own tmux session named `coconductor-${PROJECT_NAME}` (one window only). Cron sends "audit" every 15 minutes. Before each audit, cron saves a STATUS.md snapshot.
3. **Sub-agents** are one-shot `claude --print --agent` calls, each in their own dedicated tmux session named `agent-${ROLE}-${FEATURE}-${PROJECT_NAME}` (one window only). No windows inside a parent session anywhere.
4. **Double-dispatch prevention**: `tmux has-session` check before dispatching.
5. **Cron cleanup**: `devloop-stop.sh` removes cron entries tagged `# devloop-${PROJECT_NAME}` and kills all sessions.
6. **Conductor conversation history**: persistent across ticks; re-reads STATUS.md on every tick as authoritative.

**Is this architecture sound? What will break on first run? What are the risks of `tmux send-keys` as a cron trigger? What failure modes does the persistent interactive session introduce?**

---

## Advisor Responses

### The Outsider

The persistent interactive session is your biggest new risk, and you're underplaying it.

`tmux send-keys "tick" Enter` is not a reliable IPC mechanism. It sends keystrokes to whatever is currently focused in that pane. If Claude is mid-response when cron fires, you've injected "tick" into the middle of output. If the session crashed and restarted, you're sending to a fresh context with no memory. If the pane is at a prompt but Claude hung waiting on a subprocess, "tick" queues silently and fires at the wrong moment. You have no acknowledgment, no error, no log entry. The cron job always exits 0.

Conversation history is a liability disguised as a feature. The conductor "remembering what it dispatched" sounds good until the context window fills up, the model hallucinates a state that contradicts STATUS.md, or a corrupted turn poisons everything downstream. Two sources of truth competing — when they conflict, the model decides, inconsistently.

The double-dispatch check is correct but incomplete. `tmux has-session` tells you the session exists, not that the agent is still running. A finished agent whose session wasn't cleaned up blocks redispatch forever. You need exit-code-aware cleanup, not just session presence.

What breaks on first run: the cron PATH won't have tmux. Classic. Add `PATH=/usr/bin:/bin` explicitly in crontab.

The co-conductor's STATUS.md snapshot before audit — who writes it? If the conductor writes it, and the conductor is mid-tick when audit fires, you get a partial snapshot. Race condition, no lock.

The one-shot approach failed loudly. This one fails silently.

---

### The Expansionist

The architecture is sound and the shift to persistent interactive sessions is actually an underrated upgrade that unlocks stateful reasoning accumulation.

A conductor with persistent conversation history doesn't just remember what it dispatched — it builds a mental model of the project over time. It can notice "three failed QA runs on authentication in the last six ticks" without that insight being written anywhere in STATUS.md. This is emergent intelligence one-shot designs permanently forfeit.

The `tmux send-keys` trigger is not a weakness — it is an opportunity. Because the conductor is persistent, you could send it anything, not just "tick". You could send it a Slack message, a GitHub webhook payload, a user override command. The cron job is just the heartbeat. The conductor is now always listening — transforming this from a batch system into a near-real-time autonomous agent.

Dedicated session per sub-agent scales toward parallelism. Nothing prevents dispatching a spec-author and a reviewer simultaneously on different features. Parallel feature development is already latent in this design.

The conversation history length limit is the one real constraint — solvable with periodic session rotation, and a good problem to have.

---

### The Contrarian

The persistent conductor session is a liability, not a feature.

Conversation history across ticks sounds like memory, but it's actually drift. After 50+ ticks, the conductor reasons against a polluted context that contradicts the current STATUS.md. You can't flush it without killing the session — and killing the session destroys the memory. The architecture inherits the worst of both worlds: the fragility of stateful systems with none of the durability.

`tmux send-keys` fires and forgets. There is no acknowledgment, no confirmation the message was received. If Claude is processing a previous tick, the new "tick" gets injected into live output. Two concurrent tick-processing threads inside one conversation. The double-dispatch prevention on sub-agents doesn't help here — the conductor itself is the race condition.

The session-existence check is too coarse. A crashed session may linger. A completed `--print` run may or may not clean up its tmux session. You need explicit status files, not session polls.

No heartbeat, no watchdog. If the conductor session dies silently — OOM, Claude API timeout, network drop — the cron job keeps firing into a dead session. Nothing alerts. The system appears to run while doing nothing.

The co-conductor auditing a broken conductor will just document the silence.

---

### The First Principles Thinker

The stated problem is "autonomous dev loop." The real problem is: how do you maintain durable, resumable state across an AI agent that has no native persistence? Every design decision here is a workaround for that fundamental gap.

`tmux send-keys` delivers keystrokes to a terminal, not stdin to a process. If the Claude session is mid-output when cron fires, the "tick" string gets injected into the output stream or typed into a partial prompt. You get corrupted input. This is not a race condition you can tune away; it's structural.

The deeper wrong question: why is a cron job reaching into a terminal to poke an AI? This inverts the correct control flow. The conductor should be pulling triggers from a queue it owns — a file, a socket, a named pipe — not receiving injected keystrokes from outside. The terminal is an interface for humans, not a message bus.

Persistent interactive sessions accumulate: context window fills, conversation history becomes stale or contradictory, the model hallucinates continuity that doesn't exist. STATUS.md as "authoritative source" partially mitigates this, but the conductor will increasingly weight hallucinated history over the file as context grows.

Real question: should the conductor be interactive at all, or should you externalize all state to files and use `claude --resume` or fresh invocations each tick?

---

### The Executor

Mostly sound. Three things will break on first run.

**Break #1: Session target ambiguity.** `tmux has-session -t agent-spec-author-auth-BidPlatform` matches any session whose name starts with that string. Use exact-match: `tmux has-session -t "=agent-spec-author-auth-BidPlatform"` (the `=` prefix forces exact match in tmux 3.x+). Without this, double-dispatch prevention is unreliable.

**Break #2: Interactive session context drift.** After 20-30 ticks the conductor's conversation fills with STATUS.md dumps and dispatch history. Token pressure degrades reasoning quality and eventually hits context limits. Mitigation: add a tick counter to STATUS.md; at tick 50, restart the conductor session clean.

**Break #3: Cron PATH.** Add `PATH=/usr/bin:/bin` in crontab.

If cron fires while conductor is mid-response, `tmux send-keys` queues the tick in the terminal buffer. Claude sees it after finishing. Usually fine but can cause tick-doubling under slow dispatch. Acceptable risk.

Everything else — dedicated sessions per sub-agent, STATUS.md as truth source, has-session gating — is structurally correct.

---

## Peer Reviews

*(Anonymization map: A=Outsider, B=Expansionist, C=Contrarian, D=First Principles, E=Executor)*

### Reviewer 1
1. **Strongest: A** — Identifies the most consequential issues concretely. Every point is falsifiable.
2. **Biggest blind spot: B** — Reframes every flaw as a feature. "tmux send-keys is an opportunity to send Slack messages into a terminal?" Emergent intelligence is speculation. Never engages with context window exhaustion seriously.
3. **All missed:** Claude's interactive session has no documented guarantee of stdin/stdout stability under programmatic tmux injection. Does the `claude` CLI support being driven this way reliably — does it buffer input, flush cleanly, signal readiness? The entire architecture rests on an undocumented assumption about CLI behavior.

### Reviewer 2
1. **Strongest: A** — Identifies failure modes with precision. Stays grounded in what will actually break.
2. **Biggest blind spot: B** — Treats "emergent intelligence" from persistent context as real. LLM conversation history is not cumulative learning; it's a growing context window that degrades. "Conductor gets smarter over time" is false. It becomes less reliable.
3. **All missed:** Does `claude` interactive mode behave predictably when stdin is a tmux pane rather than a real terminal? PTY vs pipe semantics, signal handling, whether `claude` flushes output before waiting for the next prompt — all unknown. If `claude` buffers differently under pseudo-TTY conditions, the architecture collapses before any of the discussed failure modes matter.

### Reviewer 3
1. **Strongest: A** — Identifies concrete, compounding failure modes. E is runner-up but soft-pedals deeper structural risks.
2. **Biggest blind spot: B** — Treats persistent conversation history as a feature without addressing what happens when accumulated "mental model" contradicts ground truth.
3. **All missed:** What happens on an API rate limit, a 5xx error, or a session-level timeout mid-tick? The tmux session survives but the Claude process may have exited or stalled. Cron sends "tick" into a dead or hung process. No watchdog, no restart policy, no way to distinguish "thinking" from "dead."

### Reviewer 4
1. **Strongest: A** — Most operationally dangerous issues with specificity: PATH, exit-0 false confidence, two-sources-of-truth, session-exists != agent-running.
2. **Biggest blind spot: B** — Celebrates emergent intelligence but never addresses what happens during session rotation: all accumulated context is lost, defeating the core thesis.
3. **All missed:** Signal ordering / tick stacking. If conductor is mid-response when cron fires, tmux buffers "tick" — but what if two cron ticks queue before the first is consumed? Conductor processes tick 2 without resolving tick 1's dispatches. No debouncing. A slow LLM response on a 3-minute interval will eventually cause this.

### Reviewer 5
1. **Strongest: A** — Catches silent failure mode (tmux always exits 0), two-sources-of-truth, agent-session-lingering flaw, STATUS.md race condition.
2. **Biggest blind spot: B** — Hand-waves "session rotation is solvable" without explaining how. Most optimistic and least actionable.
3. **All missed:** Recovery when conductor dies mid-task. Sub-agent completes, writes output, nothing reads it. STATUS.md goes stale. The next cron tick fires into a dead or fresh session with no context of orphaned agents. No re-entry checkpoint. A restart procedure that reconciles STATUS.md with orphaned agent sessions before resuming is entirely absent.

---

## Chairman Synthesis

### Where the Council Agrees

All five advisors independently flagged the same three structural issues:

**`tmux send-keys` is not a message bus.** It sends keystrokes to a terminal pane with no acknowledgment, no error, and always exits 0. The cron job cannot distinguish "delivered and processed" from "injected into live output," "sent to dead session," or "queued behind two prior unprocessed ticks." Silent failure is the default.

**Persistent conversation history is a liability with an expiration date.** After enough ticks, context degrades. The conductor weights hallucinated history over STATUS.md ground truth. It looks like drift, then flakiness, then confident wrong decisions. No clean recovery without destroying the context.

**Cron PATH will break on first run.** Fix: `PATH=/usr/bin:/bin` in crontab before anything else runs.

### Where the Council Clashes

**Is persistent conversation history an upgrade or a liability?** The Expansionist argued it enables "emergent intelligence." The remaining four disagreed. LLM conversation history is not cumulative learning; it is a growing context window with a fixed ceiling. The conductor does not get smarter; it gets less reliable. The Expansionist's own proposed solution (session rotation) destroys the accumulated context it claimed was the advantage.

**How severe is tick-doubling?** The Executor called it "acceptable risk." Peer reviewers pushed back: on a 3-minute cron interval, a slow LLM response will eventually cause tick stacking. On a long-running project this is a guaranteed event.

### Blind Spots the Council Caught

**Highest-confidence finding (all 5 reviewers independently):** Does `claude` interactive mode behave predictably when stdin is a tmux pane rather than a real terminal? PTY vs pipe semantics, input buffering, output flushing, signal handling — none of this is specified in the Claude CLI. The entire architecture rests on an undocumented assumption. If `claude` buffers input differently under pseudo-TTY conditions, everything collapses before any other failure mode matters.

**API errors kill the process, not the session.** A rate limit, 5xx, or mid-tick timeout leaves the tmux session alive but the Claude process exited or hung. Cron fires into it. No watchdog, no restart policy, no way to distinguish "thinking" from "dead."

**No recovery procedure for mid-task conductor death.** Sub-agent completes and writes output. Conductor is gone. STATUS.md goes stale. The next tick fires into a fresh session with no context of orphaned agents. No re-entry checkpoint reconciles in-flight sessions with STATUS.md state.

**Tick stacking has no debounce.** If two cron firings queue before the first is consumed, conductor processes tick 2 without completing tick 1's dispatches. No deduplication mechanism exists.

### The Recommendation

The architecture is a meaningful improvement. The fatal bugs from the first council are fixed. The structural skeleton is sound. It is not production-ready. Fix in this order:

1. **Run the PONG test.** Verify `claude` interactive works correctly under tmux pseudo-TTY injection. If it fails, replace the trigger mechanism.
2. **Add cron PATH.** `PATH=/usr/bin:/bin` in crontab. Before first run.
3. **Fix tmux exact-match.** Use `tmux has-session -t "=session-name"` (the `=` prefix, tmux 3.x+).
4. **Replace session-existence check with status files.** Write `.devloop/agent-status/${ROLE}-${FEATURE}.status` with states: `running`, `complete`, `failed`. Dispatch checks the file.
5. **Add tick deduplication.** Write a lockfile at tick start, remove at tick end. If cron fires and lockfile exists, skip.
6. **Add conductor watchdog to co-conductor.** Verify the conductor is responsive, not just present.
7. **Add restart reconciliation.** When conductor restarts, scan `.devloop/agent-status/` for orphaned `running` agents, check output files, advance STATUS.md before next tick.

### The One Thing to Do First

Before writing any more code, run this test:

```bash
tmux new-session -d -s test-claude
tmux send-keys -t test-claude "claude" Enter
sleep 5
tmux send-keys -t test-claude "say the word PONG and nothing else" Enter
sleep 15
tmux capture-pane -t test-claude -p
```

If the output contains "PONG" cleanly, the foundational assumption holds and the architecture is viable. If the output is garbled, contains injection artifacts, or is empty, the trigger mechanism must be redesigned before anything else. Everything else on this fix list is premature until this test passes.

---

*Generated by LLM Council — 2026-05-04 (Council #2)*

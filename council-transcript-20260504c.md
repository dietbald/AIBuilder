# AIBuilder Council Transcript — Architecture Consistency Review
**Date:** 2026-05-04 (Council #3)
**Previous councils:** council-transcript-20260504.md, council-transcript-20260504b.md

---

## Framed Question

AIBuilder is an autonomous software development system. Do the ARCHITECTURE.md description, the agent prompt files (.claude/agents/*.md), and the startup scripts describe and implement a consistent system? Are there contradictions? Gaps where the architecture promises something the agents don't deliver? Agents that behave in ways the architecture doesn't account for?

**Context:** The system has a persistent Conductor (Claude CLI session, ticked every 3 min by cron via tmux send-keys), a persistent Co-Conductor (audited every 15 min), one-shot sub-agents in dedicated tmux sessions, STATUS.md as single source of truth, AGENT_SCHEMA.md as the output contract, session rotation at tick 50, 30-min timeout watchdog, retry logic (max 2), cross-model verification, and a spec firewall separating upstream and downstream agents.

**What's at stake:** The system runs autonomously for hours. A mismatch between the architecture doc and the implementation gives false confidence and produces failures nobody predicted.

---

## Advisor Responses

### The Executor

Tick order consistent between ARCHITECTURE.md (8 steps) and dev-conductor.md (10 steps) — the extras are prose-level details. Session names consistent everywhere across all files.

**Double-dispatch gap:** ARCHITECTURE.md specifies `tmux has-session -t "=session-name"` with `=` prefix for exact-match (explicitly called out as required to prevent false positives). dev-conductor.md hard rule #3 omits the `=` prefix — partial-name false-positives possible.

**AGENT_SCHEMA parsing gap:** dev-conductor.md "Reading Agent Output" section parses only 3 fields (verdict, output_path, notes). AGENT_SCHEMA.md defines 5 fields — also `status` and `blocking_count`. The conductor silently drops both, meaning it cannot distinguish `status: blocked` from `status: done`.

**Cross-model verification:** ARCHITECTURE.md promises the Reviewer uses a different model from the Implementer. dev-conductor.md dispatch hardcodes `--model claude-opus-4-7` for all sub-agents with no role-based model selection. Not implemented.

**`$MAX_RETRIES` in timeout watchdog:** undefined variable. The watchdog block checks `[ "$NEW_COUNT" -gt "$MAX_RETRIES" ]` but MAX_RETRIES is defined only in the retry logic section, not in the watchdog block. Comparison evaluates against an empty string in real shell execution.

---

### The Contrarian

**STATUS.md single-writer violation:** ARCHITECTURE.md says "The Conductor writes it. Nothing else writes to it." dev-reviewer.md explicitly instructs the Reviewer to update STATUS.md directly ("Update 05-progress/STATUS.md: feature → qa-testing"). dev-implementer.md does the same. Race condition with Conductor's atomic sed-and-mv.

**`review-failed` undocumented state:** The Reviewer prompt introduces state "review-failed". ARCHITECTURE.md pipeline state machine has no such state (states are: pending, speccing, spec-verifying, spec-approved, implementing, reviewing, qa-testing, done, blocked-tier4). Conductor's Action Decision Tree has no handler for "review-failed". If the Reviewer writes this to STATUS.md, the Conductor idles indefinitely on an unrecognized state.

Cross-model verification not enforced — hardcoded claude-opus-4-7 for all.

Lockfile absent — acknowledged in architecture but "blast radius is limited" claim is optimistic when two ticks queue.

---

### The First Principles Thinker

Cross-model dispatch is the unimplemented headline claim. Session rotation has a 14-minute dead window — Co-Conductor audits every 15 min, so Conductor can be dead up to 14 min before detection. Architecture implies smooth recovery; timing creates a guaranteed dead gap. Spec-author relies on $PROJECT_DIR env var inherited from session to find FEATURES.md — works but never validated at dispatch time.

---

### The Outsider

STATUS.md never populated from FEATURES.md at startup — the startup script creates an empty table; Conductor must infer features from FEATURES.md itself, but no such initialization step is described anywhere in the conductor prompt.

14-minute dead window post-rotation. Cross-model verification is architectural fiction.

**dev-test-author.md listed in README as Agent 4 but Conductor has no test-authoring status and no dispatch step** — either dead code or incomplete pipeline stage. The feature pipeline in ARCHITECTURE.md goes `implementing → reviewing` with no test-authoring step.

Tick counter resets unconditionally on restart regardless of how much context has already accumulated.

---

### The Expansionist

File-as-truth pattern (STATUS.md, RETRIES.md, DECISIONS.md) is a strong architectural asset — underexploited; could be extended to enable partial sub-agent work resumption. AGENT_SCHEMA contract is tight and consistent. Cross-model firewall strength being undersold.

Single genuine gap: dev-reviewer.md and dev-qa-tester.md both write STATUS.md in violation of single-writer rule. Everything else — session naming, dispatch timestamps, double-dispatch prevention, co-conductor action ladder — consistent end-to-end.

---

## Peer Reviews

*(Anonymization map: A=Executor, B=Contrarian, C=Outsider, D=First Principles, E=Expansionist)*

### Reviewer 1
1. **Strongest: B (Contrarian)** — Identifies STATUS.md race condition and unhandled `review-failed` state as operational failures, not just inconsistencies.
2. **Blind spot: E (Expansionist)** — Claims AGENT_SCHEMA "fully implemented" while field-count gap exists. Calls cross-model firewall a "strength being undersold" while it isn't implemented in dispatch.
3. **All missed:** RETRIES.md integrity during session rotation — if rotation triggers mid-retry-increment, the new Conductor inherits a corrupted retry count.

### Reviewer 2
1. **Strongest: B (Contrarian)** — Three distinct failure modes each with concrete consequence.
2. **Blind spot: E (Expansionist)** — Grades architecture on intentions, not implementation.
3. **All missed:** tmux `send-keys` payload truncation — shell quoting, prompt length, and tmux line-length limits can silently truncate agent instructions, causing non-deterministic failures untraceable to root cause.

### Reviewer 3
1. **Strongest: A (Executor)** — Most technically precise and falsifiable findings.
2. **Blind spot: D (First Principles)** — Restates others' points weakly; no original findings.
3. **All missed:** No defined termination condition — architecture documents a loop with no exit criterion, no mechanism to stop cron, no completion handoff. System runs indefinitely.

### Reviewer 4
1. **Strongest: A (Executor)** — Specific enough to verify by reading files.
2. **Blind spot: E (Expansionist)** — Claims schema consistent, directly contradicted by Executor's field-count finding.
3. **All missed:** tmux server restart / OS reboot — in-flight state lost silently. Most likely real-world failure path has no documented recovery.

### Reviewer 5
1. **Strongest: A (Executor)** — Line-level findings, not category-level observations.
2. **Blind spot: E (Expansionist)** — Reads like a defense brief, not an audit.
3. **All missed:** Concurrent execution atomicity — file-based coordination has no atomicity guarantee when cron timing overlaps or two events fire simultaneously.

---

## Chairman Synthesis

### Where the Council Agrees

Every advisor and every reviewer converges on three failures:

**Cross-model verification is fiction.** ARCHITECTURE.md promises the Reviewer runs on a different model from the Implementer. `dev-conductor.md` hardcodes `--model claude-opus-4-7` for all sub-agent dispatch with no role-based selection. The architectural firewall does not exist in the shell that actually runs.

**STATUS.md has multiple writers in violation of its own contract.** ARCHITECTURE.md states the Conductor is the sole writer. `dev-reviewer.md` and `dev-implementer.md` both instruct agents to update STATUS.md directly. The Conductor uses atomic sed-and-mv. Agents writing concurrently can corrupt that file or produce a version that diverges from what the Conductor expects.

**The 14-minute dead window is a gap in recovery guarantees.** The Co-Conductor audits every 15 minutes. A Conductor that dies immediately after rotation goes undetected for up to 14 minutes. The architecture implies smooth recovery. The timing math does not support that claim.

### Where the Council Clashes

The Expansionist called AGENT_SCHEMA "tight and fully consistent." The Executor measured it: dev-conductor.md parses 3 fields, AGENT_SCHEMA defines 5. `status` and `blocking_count` are silently dropped. The Executor is correct.

The Expansionist called the file-as-truth pattern a strength. The Contrarian identified it as the mechanism by which STATUS.md corruption propagates. Both are right about different things: the pattern is sound, but the multi-writer violation breaks its integrity at the point where it matters most.

### Blind Spots the Council Caught

**No termination condition.** No exit criterion for "all features done," no mechanism to stop cron, no completion handoff. The system cannot be left unattended and stopped automatically.

**RETRIES.md integrity during rotation.** Rotation mid-retry-increment leaves the new Conductor with a corrupted count. Retry exhaustion logic becomes unreliable.

**tmux `send-keys` payload truncation.** Shell quoting, prompt length, and tmux line-length limits can silently truncate agent instructions. Non-deterministic failure with no error signal.

**`dev-test-author.md` is dead code or an incomplete pipeline stage.** Listed in README as Agent 4. Conductor has no dispatch step and no corresponding state.

**tmux server restart / OS reboot wipes in-flight state silently.** The architecture has no restart-from-checkpoint mechanism for this failure mode.

**`$MAX_RETRIES` undefined in the watchdog block.** Comparison evaluates against empty string. The watchdog is effectively broken.

### The Recommendation

Fix the multi-writer violation first. Strip STATUS.md write instructions from `dev-reviewer.md` and `dev-implementer.md`. Then: parse all 5 AGENT_SCHEMA fields in the Conductor (add `status` and `blocking_count`), add a system-level termination condition, fix `$MAX_RETRIES` scope in the watchdog, and resolve the dead-code status of `dev-test-author.md`.

### The One Thing to Do First

**Remove STATUS.md write instructions from `dev-reviewer.md` and `dev-implementer.md`.**

Every other fix operates on a system whose ground truth can be corrupted at any moment. Until the single-writer contract is actually enforced — not just declared — the file-as-truth foundation the entire architecture rests on is compromised. No other fix matters if the state file cannot be trusted.

---

*Generated by LLM Council — 2026-05-04 (Council #3)*

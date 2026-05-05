# AIBuilder Council Transcript
**Date:** 2026-05-04  
**Question:** Is the AIBuilder autonomous dev system ready to run?

---

## Framed Question

TJ has built AIBuilder — a generic, reusable autonomous dev system with 15 agent prompts, 2 shell scripts, and supporting docs. It lives at `C:\Repos\e2eAiCoding\AIBuilder\` and is meant to be pointed at any software project. It uses tmux, `claude --print --agent` for headless execution, a Conductor agent that reads FEATURES.md and dispatches specialist agents, and a Co-Conductor that supervises every 15 minutes.

Critical context: `claude --print` is a one-shot call that exits after one response — it does NOT loop. The devloop-start.sh script creates a tmux session named `devloop-${PROJECT_NAME}` but the Conductor's dispatch code references `devloop` (missing the project name suffix). The system also has no inception launch path — it assumes FEATURES.md already exists.

**Is this system ready to run? What will actually break on first execution, and what must be fixed before launch?**

---

## Advisor Responses

### The Contrarian

The system cannot run. Full stop. Three fatal issues before a single line of code gets written:

**Issue 1 — The conductor is a dead man's switch with no trigger.** `claude --print` exits after one response. devloop-start.sh launches it once and walks away. There is no loop. The conductor wakes up, reads FEATURES.md, maybe dispatches one agent, then dies. Nothing relaunches it. The 15-minute co-conductor check will find a dead conductor and have no mechanism to restart it.

**Issue 2 — The tmux session name is wrong everywhere it matters.** The start script creates `devloop-BidPlatform`. The conductor's dispatch code attaches to `devloop`. These are different sessions. Every `tmux new-window -t devloop` command will either fail silently or attach to the wrong session. Feature agents will either not launch or launch in an orphaned session nobody is monitoring.

**Issue 3 — There's no inception path.** The conductor assumes FEATURES.md exists, is complete, and is structured exactly as it expects. If you run this on a new project, the conductor's first action will be to read a file that doesn't exist, produce a malformed output, and exit. No features will ever be dispatched.

The system is architecturally sound in intent. The loop bug, the naming bug, and the missing inception gate are fixable in an afternoon. But right now, as written, the system produces exactly zero features on first run. Fix the shell loop wrapper first. Everything else depends on the conductor actually running.

---

### The First Principles Thinker

The question being asked is "is this ready?" The question that matters is "what is this system actually supposed to be?"

Strip away the implementation details. What does AIBuilder do? It takes a FEATURES.md file and attempts to produce working code for each feature, autonomously, using LLM agents. The thesis is: an LLM can reliably interpret a feature specification, write tests, write implementation, review its own work, and merge — without human intervention beyond the initial spec.

That thesis has not been validated. Before asking whether the shell scripts are correct, ask whether the underlying model is sound. `claude --print` is a one-shot call — the conductor is not a persistent process, it's a series of one-shot calls pretending to be a loop. This is the category error at the center of the design.

Everything will break, once, immediately, on the first tick. Not because of a bug in a shell script, but because the architecture assumes a stateful orchestrator where none exists. The conductor's "memory" is STATUS.md — a flat file being read and written by a series of disconnected LLM calls. Race conditions, partial writes, and inconsistent reads are not edge cases here; they are the default operating mode.

The fixes are real: add the while loop, fix the tmux names, add the inception gate. But don't mistake fixing those bugs for validating the architecture. The real test is whether an LLM reading STATUS.md can make correct orchestration decisions across 10+ features over 6+ hours without human correction. That question remains open.

---

### The Expansionist

The bugs are real but they're also a gift — they're afternoon fixes, not architectural failures.

The shell loop missing is a three-line fix. The tmux naming mismatch is a one-line fix. The inception gate is a conditional check and a script call. None of these are design flaws. They're implementation oversights that exist because this was built thoughtfully but quickly.

Here's the bigger picture that every other analysis will miss: if this works at even 60% efficiency, TJ has just built something worth more than BidPlatform itself. The Philippine government procurement market is interesting. But "autonomous dev system that can build any software project" is a different category entirely. Southeast Asian govtech alone has hundreds of agencies that can't afford development teams. If AIBuilder can take a FEATURES.md and produce working code, the addressable market is every underfunded digital transformation project in ASEAN.

The three bugs are the minimum viable fix. But the real question is: what's the first project you run it on after the fixes? Don't run it on BidPlatform — too much is already built, too much context, too many edge cases. Find a greenfield project with a clean FEATURES.md and 10-15 well-defined features. Run AIBuilder against it. See what percentage of features it produces correctly. That number is the real evaluation, not whether the shell scripts compile.

Run it. Let it break. The breaks will tell you more than this council will.

---

### The Outsider

I'm looking at this from outside the technical context entirely. Three things stand out immediately:

First, the phrase "LLM conductor interprets bash pseudocode" is used as if it's a minor implementation detail. It's not. It's the entire problem. The conductor agent is an LLM that reads a markdown file containing bash-like instructions and then decides what commands to run. Every decision that conductor makes is a probabilistic inference, not a deterministic computation. When it reads "if STATUS.md shows feature X is complete, dispatch feature Y," it might do exactly that — or it might hallucinate a different reading of STATUS.md, dispatch the wrong feature, write the wrong tmux command, or decide the session name should be something else entirely.

Second, there are no observable failure modes. When this system breaks — and it will break — how does TJ know? The co-conductor checks every 15 minutes, but it's also an LLM making probabilistic decisions about whether the conductor is "healthy." The escalation goes to Telegram, but what does the Telegram message say? "Something seems wrong" is not an actionable alert.

Third, the first run isn't a soft launch. It's a single LLM call that generates an invoice and nothing else, then exits. The user won't see a dashboard, a progress bar, a log stream, or any indication that anything happened. They'll see a tmux session named `devloop-BidPlatform` with a conductor window that is either stopped or blank.

The user experience of "it's running" is completely undefined. Before fixing the loop bug, define what success looks like from the outside.

---

### The Executor

The loop doesn't loop. That's the only fact that matters right now.

devloop-start.sh launches the conductor once:
```bash
claude --print --agent "$CONDUCTOR_BOOT"
```

This runs, exits, and is never called again. Every other concern — tmux naming, inception gate, AGENTS.md paths — is irrelevant until this is fixed, because without the loop, nothing else runs.

The fix is four lines:
```bash
while true; do
  claude --print --agent "$AIBUILDER_DIR/.claude/agents/dev-conductor.md"
  sleep 180
done
```

After that, in priority order:
1. Fix the tmux session name. In dev-conductor.md, replace `devloop` with `devloop-${PROJECT_NAME}`. One grep-and-replace.
2. Add the inception gate. At the top of devloop-start.sh, before launching the conductor: check if FEATURES.md exists. If not, run the inception sequence first.
3. Update BidPlatform/AGENTS.md to remove the stale `.claude/agents/<id>.md` references.

Do not run this system before fixing #1 and #2. The loop bug means zero features produced. The tmux bug means agent windows launch in the wrong session — you won't see them, they won't be monitored, and they'll consume resources invisibly.

Fix #1 now. Fix #2 in the same commit. Gate #3 behind a successful first run.

---

## Peer Reviews

*(Anonymization map: A=Contrarian, B=First Principles, C=Expansionist, D=Outsider, E=Executor)*

### Reviewer 1
1. **Strongest: E** — Only response with executable fixes, correctly sequenced. A is close but stops at diagnosis.
2. **Biggest blind spot: C** — Pivots to TAM before confirming system can produce a single feature. Market opportunity is irrelevant until the while loop exists.
3. **All missed:** The re-entry problem. When conductor relaunches in 180 seconds, it reads STATUS.md to determine what's in-progress — but STATUS.md is being written by the agent that is still running. The relaunch cycle can dispatch the same feature twice, creating two concurrent agents writing to the same files with no locking.

### Reviewer 2
1. **Strongest: E** — Actionable, specific, with exact code and correct priority ordering.
2. **Biggest blind spot: C** — Uses bugs as launchpad for market analysis; calls inception gate "a conditional check" when FEATURES.md not existing means entire project context is undefined.
3. **All missed:** Re-entry/idempotency — conductor re-reads STATUS.md on each tick but was never written to handle partially-updated state. Double-dispatch is not theoretical; it's the default for any feature taking longer than 180 seconds.

### Reviewer 3
1. **Strongest: E** — Executable fixes, no padding, correct syntax.
2. **Biggest blind spot: C** — Dismisses inception gate as trivial; inception sequence is itself an LLM call with no validation that its output is correctly structured.
3. **All missed:** The Co-Conductor is ALSO a one-shot `claude --print` call. Who is calling it every 15 minutes? If it relies on the same shell loop, it has the same dead-on-arrival problem. The supervision layer that's supposed to catch a broken Conductor may itself be equally broken.

### Reviewer 4
1. **Strongest: E** — Prioritizes correctly, gives exact commands.
2. **Biggest blind spot: C** — Invents 60% efficiency claim; "run it and let it break" is irresponsible with no observable failure modes.
3. **All missed:** The `sleep 180` interval creates a concurrency problem. With agents running 10-30+ minutes, you will have overlapping instances writing to STATUS.md simultaneously. This survives all three proposed fixes.

### Reviewer 5
1. **Strongest: E** — No philosophical detours, executable priority queue.
2. **Biggest blind spot: C** — Market pitch evades the question; never evaluates whether LLM-reads-STATUS.md actually produces reliable orchestration.
3. **All missed:** Re-entry/idempotency — second and third conductor ticks will re-dispatch already-in-progress features if STATUS.md handling isn't designed for idempotent re-entry.

---

## Chairman Synthesis

### Where the Council Agrees

All five advisors agree on three structural defects, independently and without coordination:

**The loop does not loop.** `claude --print` is a one-shot call. devloop-start.sh launches the Conductor once and exits. Nothing relaunches it. This is not a configuration error — it is an architectural gap.

**The tmux session name is wrong.** The start script creates `devloop-${PROJECT_NAME}`. The Conductor dispatches to `devloop`. These are different sessions. Agent windows launched by the Conductor either fail or go somewhere unmonitored.

**There is no inception path.** The system assumes FEATURES.md exists. On a new project, it does not. The Conductor's first action is to read a file that isn't there, produce undefined output, and exit.

These three points achieved unanimous convergence. That makes them high-confidence defects, not opinions.

### Where the Council Clashes

**Is this a bug fix or an architectural rethink?**

The Contrarian and Executor treat the three defects as implementation oversights — fixable in an afternoon, system is then launchable. The First Principles Thinker argues the loop bug is a symptom of a category error: the design assumes a stateful orchestrator, but what it has is a series of disconnected one-shot LLM calls sharing a flat file. Fixed or not, whether an LLM reading STATUS.md can make correct orchestration decisions across hours is an unvalidated thesis.

E wins the immediate question ("what breaks on first run"). B wins the subsequent question ("what breaks on the tenth run").

**Is the inception gate an afternoon fix or a missing product requirement?**

The Expansionist calls it "a conditional check and a script call." But if FEATURES.md doesn't exist, the entire project context is undefined — the inception sequence is itself an LLM call with no validation that its output is correctly structured. The inception gate is not a guard clause; it is a bootstrapping problem.

### Blind Spots the Council Caught

**The re-entry and double-dispatch problem.** All five peer reviewers flagged this independently. When the Conductor relaunches after `sleep 180`, it reads STATUS.md to determine what's in progress — but STATUS.md is being written by agents that are still running. The Conductor has no mechanism to detect in-progress work. It will re-dispatch already-running features. Two concurrent agents will write to the same files with no locking, no coordination, and no recovery path. This is the default operating mode for any feature taking longer than three minutes.

**The Co-Conductor has the same dead-on-arrival problem.** All five advisors described the Co-Conductor as a background supervisor that "checks every 15 minutes" — but who is calling it every 15 minutes? If it relies on the same shell loop mechanism, it is also a one-shot call that runs once and exits. The supervision layer may be broken in exactly the same way as the Conductor.

### The Recommendation

The system is not ready to run. Fix three things in this order:

1. Add the while loop in devloop-start.sh. This is the load-bearing fix.
2. Fix the tmux session name in dev-conductor.md. One grep-and-replace. Must happen in the same commit as the loop fix.
3. Add idempotency handling to the Conductor's STATUS.md read logic. The Conductor must explicitly skip features marked `in-progress` or `complete` on re-entry. Without this, fix #1 makes double-dispatch structural and permanent.

Do not launch before all three. Do not treat #3 as optional — it becomes mandatory the moment the loop exists.

The Co-Conductor's scheduling mechanism must also be audited before the first real run.

### The One Thing to Do First

Read dev-conductor.md and devloop-start.sh in full before writing a single line of fix code. Every proposed fix in this council was written without confirming exactly how STATUS.md is read, written, and interpreted on re-entry. The loop fix is useless if the Conductor's prompt re-dispatches in-progress features on every tick. The actual text of those two files determines whether the fix is four lines or forty.

---

*Generated by LLM Council — 2026-05-04*

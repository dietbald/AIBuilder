# Council Transcript — Council #5
Date: 2026-05-05
Topic: AIBuilder readiness audit — is it ready to run on a real project?

---

## Original Question

AIBuilder is an autonomous multi-agent software development system built on Claude Code CLI. After 4 rounds of audits fixing 21 issues, it's been published to GitHub at https://github.com/dietbald/AIBuilder. Is it ready to run on a real project? What would stop it?

---

## Advisor → Letter Mapping

| Letter | Advisor |
|---|---|
| A | The Contrarian |
| B | The First Principles Thinker |
| C | The Expansionist |
| D | The Outsider |
| E | The Executor |

---

## Response A — The Contrarian

Five things that will break on first run (found by reading actual agent files):

**1. `--agent` does not accept a file path.** The Claude CLI `--agent` flag accepts a registered agent name, not an arbitrary file path. The dispatch block builds a throwaway prompt file at `/tmp/devloop-prompt-${ROLE}-${FEATURE}.txt` and passes that path directly. The command will error or silently ignore the file. Every sub-agent dispatch is broken on this assumption.

**2. Co-conductor restart injects STATUS.md verbatim into tmux send-keys.** `STATUS_SUMMARY=$(cat STATUS.md)` embedded in a single tmux send-keys string. On a real project, STATUS.md contains newlines, pipes, quotes, backticks. tmux treats each newline as Enter — fires the command after the first line, sends the rest as separate shell commands, corrupting shell state entirely.

**3. dev-spec-verifier.md writes STATUS.md directly (lines 96–97).** Single-writer contract violation. Race condition with concurrent Conductor writes guaranteed.

**4. dev-deployer.md uses `git add -p` — interactive TUI.** Blocks the headless `--print` session permanently. The agent hangs until the 30-minute watchdog kills it every time. The pipeline can never ship to staging autonomously.

**5. dev-auditor.md says "Best CLI: Gemini 2.5 Pro" but Conductor has no Gemini dispatch path.** Auditor either runs on Sonnet (defeating cross-model rationale) or never runs at all.

---

## Response B — The First Principles Thinker

The system is trying to replace a human engineering team with a state machine. Three structural failures:

**CLI invocation is unverified.** `claude --print --agent <file>` may not be valid syntax. If the flag combination doesn't work, no sub-agent has ever run. The entire pipeline is a no-op dressed in scaffolding. This must be confirmed empirically before any other analysis matters.

**Environment is not inherited across tmux sessions.** Tmux sessions are independent login shells. API keys, PATH, working directory assumptions — none propagate automatically. Sub-agents likely spawn into a bare environment.

**State machine has no stuck-feature timeout.** If a sub-agent silently fails, the feature sits in its current stage forever. The watchdog detects conductor death but not sub-agent failure that produces no output.

Until CLI syntax and environment inheritance are verified empirically, every other readiness question is premature.

---

## Response C — The Expansionist

The public repo is the starting gun for an AI-native software factory. The real opportunity: can this model be franchised?

The Inception phase is a standalone enterprise product — "Product Blueprint as a Service." Interactive BA + TechStack + Brand agents that produce a verified spec before a line of code is written? Sell this to enterprises independently.

The cross-model verification pattern (Sonnet implements, Opus reviews) is a publishable architecture. A whitepaper alone could drive significant developer mindshare.

DECISIONS.md transcripts from each project are a training corpus. Cross-project learning compounds.

Ship BidPlatform with it publicly. The process is the product.

---

## Response D — The Outsider

**No `claude` CLI install guide.** README lists it as prerequisite but has no link, no install command, no mention of API key requirement. User hits "command not found" with nowhere to go.

**`openclaw` is listed as optional but unexplained.** Is it a package? A paid service? A script?

**No mental model for interactive vs headless agent modes.** The BA agent asks questions interactively but the system otherwise runs headless. A new user has no idea when they're talking to an agent vs watching one run.

**Unclear what "project directory" means.** Does FEATURES.md live in the same directory as the code being built? A separate directory? The cron session naming convention isn't shown.

The system assumes tmux expertise, Claude CLI knowledge, and file layout intuition that are never documented at the entry point.

---

## Response E — The Executor

Four concrete blockers in priority order:

**Blocker 1:** `--print --agent` flag combination unverified. If they don't compose, every sub-agent dispatch silently fails. Pipeline stalls at tick one.

**Blocker 2:** Env vars not exported to sub-agent tmux sessions. The dispatch block embeds values in PROMPT_FILE but the sub-agent bash environment has no `PROJECT_DIR`. Fix: prepend `export PROJECT_DIR='...' AIBUILDER_DIR='...' PROJECT_NAME='...' &&` before the `claude` call.

**Blocker 3:** FEATURES.md format mismatch — inception uses `### Feature Name` under `## P0 — Core`, not `## F-01-slug`. devloop-start.sh regex `^## (F-[0-9]+...)` never matches. STATUS.md stays empty.
*(Note: Reviewer 4 confirmed this claim is WRONG — devloop-start.sh lines 74-80 handle both format variants.)*

**Blocker 4:** Cron fires into dead tmux server after machine sleep. Command exits 0 silently, conductor never gets tick.

Monday order: test `claude --print --agent FILE` manually. If it works, fix env export.

---

## Peer Reviews

### Reviewer 1
- **Strongest:** A (5 specific falsifiable bugs with file references)
- **Biggest blind spot:** C (answers a different question — zero blockers)
- **All missed:** Idempotency — what happens when devloop-start.sh runs on a partially complete project? STATUS.md mid-flight, does conductor resume or overwrite?

### Reviewer 2
- **Strongest:** A (highest-signal technical audit)
- **Biggest blind spot:** C (non-answer)
- **All missed:** No minimum viable ops loop — silent failure is operationally indistinguishable from normal operation. No mechanism to surface "agent X silent for 40 min" as an alert.

### Reviewer 3
- **Strongest:** A
- **Biggest blind spot:** C
- **All missed:** No ground truth — the system has never been run end-to-end. No acceptance criterion for "ready." Need one feature, end-to-end, live.

### Reviewer 4 (also read actual files)
- **Strongest:** A (bugs confirmed — git add -p confirmed dev-deployer.md line 32; spec-verifier STATUS.md write confirmed lines 96-97)
- **Biggest blind spot:** E's FEATURES.md format mismatch claim is WRONG — devloop-start.sh lines 74-80 explicitly handle both formats. E invented a bug that doesn't exist.
- **All missed:** Co-conductor Level 3 restart sends STATUS.md via tmux send-keys unescaped — same as A's bug #2, confirmed by file read.

### Reviewer 5
- **Strongest:** A
- **Biggest blind spot:** A missed priority ordering — Bug 1 makes all others moot
- **All missed:** System has never been run end-to-end. Not a debugging problem — an empirical unknown.

---

## Chairman's Verdict

### Where the Council Agrees

Every advisor with technical depth agrees: `claude --print --agent <file>` is unverified and may not work. This is the single load-bearing assumption the entire system rests on.

Four specific bugs survived peer review with file confirmation:
- `git add -p` in dev-deployer.md blocks headless sessions permanently
- dev-spec-verifier.md writes STATUS.md directly — single-writer violation, race condition guaranteed
- Co-conductor restart injects raw STATUS.md via tmux send-keys — shatters on newlines, pipes, quotes
- Env vars not exported to sub-agent tmux sessions

The Expansionist was unanimously dismissed as non-responsive.

### Where the Council Clashes

**Factual dispute resolved:** The Executor's FEATURES.md regex mismatch claim is wrong. devloop-start.sh handles both format variants. Bug doesn't exist.

**Unresolved:** Whether the Auditor model selection failure (Gemini claim vs. claude-only dispatch) is a real bug or documentation artifact. No one confirmed it by reading the dispatch logic.

**Epistemic split:** Specificity with file grounding (Contrarian) beat abstraction (First Principles) and beat lists (Executor).

### Blind Spots the Council Caught

**Idempotency.** What happens when devloop-start.sh runs against a project with STATUS.md mid-flight? Does conductor resume or overwrite? Untested and undocumented.

**Silent failure is operationally invisible.** The watchdog detects conductor death; it doesn't detect sub-agent stalls. On a real project you won't know something is wrong until you check manually.

**System has never been run end-to-end.** This is an empirical unknown, not a code review problem. No one has watched a feature go from FEATURES.md to deployed code. The council spent its analysis on a system that may or may not function when executed.

### The Recommendation

**No. It is not ready to run on a real project.**

The blockers are execution failures, not documentation gaps: a core invocation that may be syntactically invalid, an interactive command that permanently hangs headless sessions, a multi-writer race on the state file, and a tmux injection that corrupts shell state on any real project.

The Expansionist's vision is downstream of a system that can complete one feature end-to-end.

### The One Thing to Do First

Open a terminal. Run this manually:

```
claude --print --agent /path/to/any-agent.md "test prompt"
```

**If it errors:** The entire dispatch architecture needs to be redesigned. Find the correct flag combination for headless agent invocation and rebuild dispatch around it.

**If it succeeds:** You have confirmed the load-bearing assumption. Then fix `git add -p`, fix the STATUS.md single-writer violation in dev-spec-verifier.md, and escape the tmux send-keys injection in the co-conductor restart. Then run one feature, live, watched, on a throwaway repo.

Everything else is conjecture until that command returns a result.

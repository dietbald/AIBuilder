# AIBuilder

Autonomous end-to-end software development system. Give it a project with a `FEATURES.md` and it writes specs, implements features, reviews code, runs QA, and deploys to staging — without you watching.

**You only get involved for Tier 4 escalations** (business decisions, expired API keys, retry ceilings exceeded). Everything else is handled autonomously.

---

## How It Works

```
FEATURES.md  →  Inception (6 agents, TJ participates)  →  devloop-start.sh
                                                                   ↓
                                          Conductor (runs forever, ticked every 3 min)
                                                   ↓
           Spec Author → Spec Verifier → Implementer → Test Author → Reviewer → QA Tester → Deployer
                                                   ↓
                                          Co-Conductor (audits every 15 min)
                                          Telegram alerts on stall / drift / failure
                                                   ↓
                              (all features done) → COMPLETION.md + cron stopped
```

The **Conductor** is a persistent Claude session that ticks every 3 minutes. It reads `STATUS.md`, dispatches one agent per tick, processes completions, and advances the pipeline. The **Co-Conductor** watches the Conductor and restarts it if it stalls or dies.

---

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `tmux` | Persistent sessions for conductor, co-conductor, and agents | `apt install tmux` / `brew install tmux` |
| `claude` CLI | Powers all agents | [Claude Code install guide](https://claude.ai/code) |
| `bash` 4+ | Scripts | Ships with Linux/macOS |
| `openclaw` | Telegram alerts | Install via openclaw docs (optional — alerts are skipped if not configured) |

Verify prerequisites:
```bash
tmux -V          # must be 3.x+ for exact-match session checks
claude --version
bash --version
```

---

## Directory Structure

```
AIBuilder/
├── README.md                    ← you are here
├── AGENT_SCHEMA.md              ← output contract all agents must follow
├── STRESS_TESTS.md              ← gate tests before first production run
├── TIER4-RUNBOOK.md             ← your recovery guide when escalations arrive
├── scripts/
│   ├── devloop-start.sh         ← launches the system for a project
│   └── devloop-stop.sh          ← shuts down cleanly
└── .claude/agents/
    ├── dev-conductor.md         ← Conductor (Agent 0) — the orchestrator
    ├── co-conductor.md          ← Co-Conductor — supervisor and watchdog
    ├── inception-ba.md          ← Inception: Business Analyst
    ├── inception-techstack.md   ← Inception: Tech Stack decider
    ├── inception-brand.md       ← Inception: Brand and tone
    ├── inception-domain.md      ← Inception: Domain model
    ├── inception-infra.md       ← Inception: Infrastructure setup
    ├── inception-scaffold.md    ← Inception: Project scaffolding
    ├── dev-spec-author.md       ← Agent 1: Writes feature specs
    ├── dev-spec-verifier.md     ← Agent 2: Verifies specs are complete
    ├── dev-implementer.md       ← Agent 3: Implements code test-first
    ├── dev-test-author.md       ← Agent 4: Writes e2e tests
    ├── dev-reviewer.md          ← Agent 5: Cross-model code review gate
    ├── dev-qa-tester.md         ← Agent 6: Runs the real app in a browser
    ├── dev-auditor.md           ← Agent 7: Cross-feature audits
    └── dev-deployer.md          ← Agent 8: Staging deploy
```

---

## Phase 1 — Inception (one-time, you participate)

Inception produces everything the development loop needs: `FEATURES.md`, `domain.md`, `brand.md`, `techstack.md`, `CODING_STANDARDS.md`, and the initial project scaffold.

Run the inception agents **sequentially**, one at a time. Each agent reads the previous agent's output.

```bash
AIBUILDER_DIR="/path/to/AIBuilder"
PROJECT_DIR="/path/to/your/project"

cd "$PROJECT_DIR"

# I-1: Business Analyst — defines features and acceptance criteria
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-ba.md"

# I-2: Tech Stack — decides languages, frameworks, packages
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-techstack.md"

# I-3: Brand — tone, naming conventions, UI style
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-brand.md"

# I-4: Domain — models the core domain concepts
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-domain.md"

# I-5: Infra — sets up cloud infrastructure and CI/CD
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-infra.md"

# I-6: Scaffold — generates the project skeleton from the above
claude --agent "$AIBUILDER_DIR/.claude/agents/inception-scaffold.md"
```

> **Your role during inception:** The BA agent (I-1) will ask you questions via `AskUserQuestion`. Answer them. The rest are largely autonomous but may surface questions. When inception is complete, the project directory has everything the development loop needs.

After inception completes, verify these files exist before starting the dev loop:

```bash
ls "$PROJECT_DIR/FEATURES.md"          # feature list with acceptance criteria
ls "$PROJECT_DIR/AGENTS.md"            # project-specific agent rules
ls "$PROJECT_DIR/CODING_STANDARDS.md"  # coding contract
ls "$PROJECT_DIR/05-progress/STATUS.md" # will be created by devloop-start.sh if missing
```

---

## Phase 2 — Start the Development Loop

```bash
bash /path/to/AIBuilder/scripts/devloop-start.sh /path/to/your/project
```

This script:
1. Verifies `AGENTS.md` and `FEATURES.md` exist
2. Creates required directories (`02-specs/`, `05-progress/`, `.devloop/`)
3. Initializes `STATUS.md` if missing
4. Launches `conductor-<PROJECT>` tmux session (interactive Claude)
5. Launches `coconductor-<PROJECT>` tmux session (interactive Claude)
6. Installs two cron jobs: conductor ticked every 3 min, co-conductor audited every 15 min

**Example:**

```bash
bash /c/Repos/e2eAiCoding/AIBuilder/scripts/devloop-start.sh /c/Repos/MyProject
```

Output:
```
================================================================
DevLoop AIBuilder
AIBuilder:      /c/Repos/e2eAiCoding/AIBuilder
Project:        /c/Repos/MyProject
Conductor:      conductor-MyProject
Co-Conductor:   coconductor-MyProject
================================================================
Launching Conductor...
Launching Co-Conductor...
Cron installed: conductor ticked every 3 min, co-conductor audited every 15 min.
================================================================
DevLoop is running.

  Conductor:      tmux attach -t conductor-MyProject
  Co-Conductor:   tmux attach -t coconductor-MyProject

  Status:         cat '/c/Repos/MyProject/05-progress/STATUS.md'
  Cron check:     crontab -l | grep devloop
  Stop:           bash '/c/Repos/e2eAiCoding/AIBuilder/scripts/devloop-stop.sh' '/c/Repos/MyProject'
================================================================
```

---

## Monitoring

### Watch the pipeline state

```bash
# Overall feature progress
cat /path/to/project/05-progress/STATUS.md

# Structured event log — every dispatch, completion, failure, and state transition
tail -f /path/to/project/05-progress/devloop-event.log

# What the conductor did on each tick (one-line summaries)
tail -f /path/to/project/05-progress/conductor-log.md

# Co-conductor audit log
tail -f /path/to/project/.devloop/co-conductor.log
```

### Watch live sessions

```bash
# Attach to conductor (read-only — don't type into it)
tmux attach -t conductor-MyProject

# Attach to co-conductor
tmux attach -t coconductor-MyProject

# See all active agent sessions
tmux list-sessions | grep agent-

# Watch a specific agent's output as it runs
tail -f /tmp/devloop-out-dev-spec-author-F-01.txt
```

### Check what's currently running

```bash
# All tmux sessions for this project
tmux list-sessions | grep -E "conductor-MyProject|agent-.*-MyProject"

# Cron jobs installed
crontab -l | grep devloop

# Retry budget remaining per feature
cat /path/to/project/05-progress/RETRIES.md

# Tick count (resets to 0 at 50 for session rotation)
cat /path/to/project/.devloop/tick-count
```

---

## Stopping

```bash
bash /path/to/AIBuilder/scripts/devloop-stop.sh /path/to/your/project
```

This kills all tmux sessions for the project (conductor, co-conductor, and all agent sessions) and removes the cron entries. `STATUS.md` is preserved — you can restart from where it stopped.

---

## Restarting from a Stopped State

STATUS.md records exactly where the pipeline stopped. The Conductor reads it on startup and resumes from there — it does not re-do completed stages.

```bash
bash /path/to/AIBuilder/scripts/devloop-start.sh /path/to/your/project
```

---

## When You Get a Telegram Alert

Telegram alerts mean the system has hit something it cannot resolve autonomously. Open `TIER4-RUNBOOK.md` — it walks you through every failure type:

- **Persistent rate limit** — quota exhausted; wait or upgrade
- **Expired API key** — re-authenticate and relaunch
- **Git push failure** — re-authenticate with `gh auth login`
- **Retry ceiling exceeded** — agent failed 2× with notes; your judgment needed on whether to rewrite the spec, override the verifier, or decompose the feature

After fixing, restart:
```bash
bash /path/to/AIBuilder/scripts/devloop-start.sh /path/to/your/project
```

---

## Configuring Telegram Alerts

Add to `<project-dir>/.devloop/config`:

```
TELEGRAM_TARGET=@your_telegram_username
```

If this file doesn't exist or `TELEGRAM_TARGET` is not set, alerts are skipped and logged locally only.

---

## Before First Production Run

Run the stress tests in `STRESS_TESTS.md` in order. **ST-01 (the PONG test) is a hard gate** — if it fails, the entire trigger mechanism needs to be replaced before anything else runs.

```bash
# ST-01 — verify claude interactive mode works under tmux injection
tmux new-session -d -s test-claude
tmux send-keys -t test-claude "claude" Enter
sleep 5
tmux send-keys -t test-claude "say the word PONG and nothing else" Enter
sleep 15
tmux capture-pane -t test-claude -p
tmux kill-session -t test-claude
# Output must contain the word PONG cleanly
```

See `STRESS_TESTS.md` for the full list.

---

## Key Files in a Running Project

| File | Owner | Purpose |
|---|---|---|
| `05-progress/STATUS.md` | Conductor | Authoritative pipeline state — do not edit manually |
| `05-progress/devloop-event.log` | Conductor | Structured event log — every dispatch, completion, failure, state transition |
| `05-progress/conductor-log.md` | Conductor | One-line log per tick |
| `05-progress/RETRIES.md` | Conductor | Retry counters per feature/role |
| `05-progress/DECISIONS.md` | Conductor | All Tier 1–3 resolution decisions |
| `02-specs/<feature>/spec.md` | Spec Author | The contract each feature is built against |
| `.devloop/co-conductor.log` | Co-Conductor | Audit log |
| `.devloop/co-conductor-alert.md` | Co-Conductor | Written when Tier 4 escalation happens |
| `.devloop/tick-count` | Conductor | Current tick number (resets at 50) |
| `.devloop/agent-dispatch/*.time` | Conductor | Dispatch timestamps for timeout watchdog |
| `/tmp/devloop-out-<role>-<feature>.txt` | Agents | Agent output (read by Conductor after completion) |

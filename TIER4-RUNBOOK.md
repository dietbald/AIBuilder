# TIER4-RUNBOOK.md — TJ's Recovery Guide

This file is for TJ. You get here because you received a Telegram from the Co-Conductor or Conductor that the pipeline has stalled and cannot self-recover.

**Do not panic. STATUS.md shows exactly where it stopped. You resume from there, not from scratch.**

---

## Step 1 — Read the Telegram message

The message tells you which Tier 4 condition fired. Note:
- Which project and feature (`F-XX`)
- Which role (`spec-verifier`, `implementer`, etc.)
- What went wrong (rate limit, auth failure, retry ceiling, git failure)

---

## Step 2 — Check current state (takes 2 minutes)

```bash
# Where did it stop?
cat <project-dir>/05-progress/STATUS.md

# What was the last agent doing?
ls -lt /tmp/devloop-out-*.txt | head -5

# Read the tail of the most recent output
tail -40 /tmp/devloop-out-<role>-<feature>.txt

# How many retries were used?
cat <project-dir>/05-progress/RETRIES.md

# Co-Conductor log (what it observed)
tail -20 <project-dir>/.devloop/co-conductor.log
```

---

## Step 3 — Fix by failure type

### Persistent rate limit (quota exhausted)

```bash
# Check the rate limit error in the agent output file
grep -i '429\|rate.limit\|overloaded' /tmp/devloop-out-<role>-<feature>.txt

# Options:
# A) Wait — Claude rate limits reset hourly or daily
# B) Upgrade Anthropic plan quota

# Clear the rate-limit counter for this agent so it gets 3 fresh backoffs
grep -v "^F-XX:<role>:rate-limit=" <project-dir>/05-progress/RETRIES.md \
  > <project-dir>/05-progress/RETRIES.md.tmp \
  && mv <project-dir>/05-progress/RETRIES.md.tmp <project-dir>/05-progress/RETRIES.md
```

---

### Expired or wrong API key

```bash
# Identify which key is failing from the output file
grep -i 'auth\|unauthorized\|invalid.key\|403' /tmp/devloop-out-<role>-<feature>.txt

# Fix: update the Anthropic API key in your shell environment or .env file
# ANTHROPIC_API_KEY

# Verify the new key works before relaunching:
curl -s -o /dev/null -w "%{http_code}" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  https://api.anthropic.com/v1/models
# Should return 200
```

---

### Git push failure

```bash
# Read the git error from the output file (deployer output, not conductor — conductor is a
# persistent session and does not write to /tmp/devloop-out-*.txt)
tail -20 /tmp/devloop-out-dev-deployer-F-*.txt | grep -i 'git\|push\|auth\|reject'

# Common fixes:
# Auth failure   → gh auth login  (re-authenticate with GitHub CLI)
# Branch protect → check if you need a PR instead of direct push
# Force required → git pull --rebase origin main  (resolve diverged history)

# Once fixed, verify manually:
git -C <project-dir> status
git -C <project-dir> log --oneline -5
```

---

### Retry ceiling exceeded (semantic failure)

This means the agent failed 3 total times (original attempt + 2 retries) with notes injected, and still couldn't pass the verifier. This needs your judgment.

```bash
# Read the last failure notes
grep 'notes:' /tmp/devloop-out-<role>-<feature>.txt | tail -5

# Read the spec that kept failing
cat <project-dir>/02-specs/F-XX-<slug>/spec.md

# Read the verifier's full report
cat <project-dir>/05-progress/qa-reports/F-XX-*.md | tail -50
```

**Options:**
- **The spec is genuinely bad** → delete `02-specs/F-XX-*/spec.md`, clear the retry counter, let spec-author rewrite from scratch with context you add to the prompt.
- **The verifier is being unreasonably strict** → read the notes, decide if they're valid. If not: clear the retry counter and re-dispatch with a note saying "previous failure reason was: [X] — this is acceptable for our use case, treat as PASS if the spec otherwise meets the criteria."
- **The feature needs human decomposition** → split it into two smaller features in FEATURES.md, update STATUS.md to remove the blocked entry, restart.

```bash
# Clear retry counter for this feature/role:
grep -v "^F-XX:<role>=" <project-dir>/05-progress/RETRIES.md \
  > <project-dir>/05-progress/RETRIES.md.tmp \
  && mv <project-dir>/05-progress/RETRIES.md.tmp <project-dir>/05-progress/RETRIES.md
```

---

## Step 4 — Relaunch

STATUS.md records where the pipeline stopped. The Conductor reads it on startup and resumes from there — it does not re-do completed stages.

```bash
# Relaunch the full devloop session:
bash <aibuilder-dir>/scripts/devloop-start.sh <project-dir>
```

If the tmux sessions still exist from the previous run, kill them first:

```bash
PROJECT_NAME=$(basename <project-dir>)
tmux kill-session -t "=conductor-${PROJECT_NAME}"   2>/dev/null || true
tmux kill-session -t "=coconductor-${PROJECT_NAME}" 2>/dev/null || true
bash <aibuilder-dir>/scripts/devloop-start.sh <project-dir>
```

---

## What NOT to do

- **Do NOT edit STATUS.md manually** unless you know exactly what you're doing. A wrong edit will cause the Conductor to re-do or skip work. If you must edit it, use the atomic write pattern (write to .tmp, then mv).
- **Do NOT clear RETRIES.md entirely** — this resets ALL retry budgets, not just the blocked one. Clear only the specific key for the blocked feature/role.
- **Do NOT re-run inception** — it is already complete. Relaunching devloop-start.sh goes straight to the Conductor.
- **Do NOT delete STATUS.md** — it is the only durable state. Deleting it means the pipeline restarts from feature 1.

---

## If the Co-Conductor itself is dead

```bash
# Check what sessions are running
tmux list-sessions

# If both conductor and co-conductor are gone, relaunch everything:
bash <aibuilder-dir>/scripts/devloop-start.sh <project-dir>

# If only co-conductor is dead but conductor is still running, restart just the co-conductor:
PROJECT_NAME=$(basename <project-dir>)
AIBUILDER_DIR=<aibuilder-dir>
COCONDUCTOR_AGENT="$AIBUILDER_DIR/.claude/agents/co-conductor.md"

tmux kill-session -t "=coconductor-${PROJECT_NAME}" 2>/dev/null || true
tmux new-session -d -s "coconductor-${PROJECT_NAME}" -x 220 -y 50
tmux send-keys -t "=coconductor-${PROJECT_NAME}" \
  "export PROJECT_DIR='<project-dir>' AIBUILDER_DIR='<aibuilder-dir>' PROJECT_NAME='$PROJECT_NAME'" Enter
sleep 1
# --agent takes a name, not a file path (agents symlinked to ~/.claude/agents/ by devloop-start.sh)
# --dangerously-skip-permissions required for headless dispatch — trust dialog hangs otherwise
tmux send-keys -t "=coconductor-${PROJECT_NAME}" \
  "cd '<project-dir>' && claude --model claude-sonnet-4-6 --dangerously-skip-permissions --agent co-conductor" Enter
sleep 8
tmux send-keys -t "=coconductor-${PROJECT_NAME}" "" Enter
```

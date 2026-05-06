#!/usr/bin/env bash
# devloop-start.sh
# Launches the DevLoop autonomous development pipeline for a project.
#
# Usage: bash /path/to/AIBuilder/scripts/devloop-start.sh <project-dir>
# Example: bash /c/Repos/e2eAiCoding/AIBuilder/scripts/devloop-start.sh /c/Repos/e2eAiCoding/BidPlatform
#
# Creates two tmux sessions (one window each):
#   conductor-<PROJECT>     — interactive Claude conductor, ticked by cron every 3 min
#   coconductor-<PROJECT>   — interactive Claude co-conductor, ticked by cron every 15 min
#
# To stop:
#   bash /path/to/AIBuilder/scripts/devloop-stop.sh <project-dir>

set -euo pipefail

AIBUILDER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

CONDUCTOR_SESSION="conductor-${PROJECT_NAME}"
COCONDUCTOR_SESSION="coconductor-${PROJECT_NAME}"

CONDUCTOR_AGENT="$AIBUILDER_DIR/.claude/agents/dev-conductor.md"
COCONDUCTOR_AGENT="$AIBUILDER_DIR/.claude/agents/co-conductor.md"

echo "================================================================"
echo "DevLoop AIBuilder"
echo "AIBuilder:      $AIBUILDER_DIR"
echo "Project:        $PROJECT_DIR"
echo "Conductor:      $CONDUCTOR_SESSION"
echo "Co-Conductor:   $COCONDUCTOR_SESSION"
echo "================================================================"
echo ""

# ── Verify project directory ──────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/AGENTS.md" ]; then
  echo "ERROR: $PROJECT_DIR/AGENTS.md not found."
  echo "Is this a valid DevLoop project? Expected AGENTS.md at project root."
  exit 1
fi

if [ ! -f "$PROJECT_DIR/FEATURES.md" ]; then
  echo "ERROR: $PROJECT_DIR/FEATURES.md not found."
  echo "Run Inception phase first before starting the development loop."
  exit 1
fi

if [ ! -f "$PROJECT_DIR/CODING_STANDARDS.md" ]; then
  echo "WARNING: $PROJECT_DIR/CODING_STANDARDS.md not found."
  echo "         Development agents require this file. Run inception-scaffold first."
  echo "         Continuing — Conductor will warn when agents try to read it."
fi

# ── Create required directories ───────────────────────────────────────
mkdir -p "$PROJECT_DIR/02-specs"
mkdir -p "$PROJECT_DIR/05-progress/qa-reports"
mkdir -p "$PROJECT_DIR/.devloop"
mkdir -p "$PROJECT_DIR/.devloop/agent-dispatch"

# ── Initialize STATUS.md if it doesn't exist ─────────────────────────
if [ ! -f "$PROJECT_DIR/05-progress/STATUS.md" ]; then
  cat > "$PROJECT_DIR/05-progress/STATUS.md" << EOF
# STATUS.md — DevLoop Pipeline State
Initialized: $(date)

| Feature | Status |
|---|---|
EOF
  echo "STATUS.md initialized."
fi

# ── Populate STATUS.md from FEATURES.md if it has no feature rows ─────
# This handles fresh starts where Inception wrote FEATURES.md but not STATUS.md.
# Supports header formats: "## F-01-slug-name", "## F-01: Title", "## F-01 — Title"
if ! grep -q '| F-' "$PROJECT_DIR/05-progress/STATUS.md" 2>/dev/null; then
  echo "No features in STATUS.md — populating from FEATURES.md..."
  FEATURE_COUNT=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ (F-[0-9]+(-[a-z0-9]+)+) ]]; then
      FID="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##\ (F-[0-9]+) ]]; then
      FID="${BASH_REMATCH[1]}"
    else
      continue
    fi
    echo "| $FID | pending |" >> "$PROJECT_DIR/05-progress/STATUS.md"
    echo "  Added feature: $FID"
    FEATURE_COUNT=$(( FEATURE_COUNT + 1 ))
  done < "$PROJECT_DIR/FEATURES.md"
  if [ "$FEATURE_COUNT" -eq 0 ]; then
    echo "WARNING: No F-## feature headers found in FEATURES.md."
    echo "         Expected lines like '## F-01-user-auth' or '## F-01: User Auth'"
    echo "         Conductor will idle until features are added to STATUS.md manually."
  else
    echo "  Populated $FEATURE_COUNT features into STATUS.md."
  fi
fi

# ── Initialize RETRIES.md if it doesn't exist ────────────────────────
if [ ! -f "$PROJECT_DIR/05-progress/RETRIES.md" ]; then
  cat > "$PROJECT_DIR/05-progress/RETRIES.md" << EOF
# RETRIES.md — Persistent retry counters
# Format: FEATURE:ROLE=N
EOF
fi

# ── Reset tick counter (fresh start) ─────────────────────────────────
echo "0" > "$PROJECT_DIR/.devloop/tick-count"

# ── Clean up orphaned temp files from a previous crashed run ──────────
rm -f "$PROJECT_DIR/05-progress/STATUS.md.tmp"   2>/dev/null || true
rm -f "$PROJECT_DIR/05-progress/RETRIES.md.tmp"  2>/dev/null || true

# ── Initialize structured event log ──────────────────────────────────
EVENT_LOG="$PROJECT_DIR/05-progress/devloop-event.log"
if [ ! -f "$EVENT_LOG" ]; then
  echo "# DevLoop Event Log — $PROJECT_NAME — started $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$EVENT_LOG"
fi
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | system | devloop | started | project=$PROJECT_NAME" >> "$EVENT_LOG"

# ── Install agent symlinks ────────────────────────────────────────────
# claude --agent <name> resolves from ~/.claude/agents/ (user-level) and
# <cwd>/.claude/agents/ (project-level). Symlinking here means agents are
# always discoverable regardless of which cwd the sub-agent sessions use.
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
mkdir -p "$CLAUDE_AGENTS_DIR"
echo "Installing agent symlinks..."
for agent_file in "$AIBUILDER_DIR/.claude/agents/"*.md; do
  agent_name=$(basename "$agent_file" .md)
  ln -sf "$agent_file" "$CLAUDE_AGENTS_DIR/$agent_name.md"
done
echo "  Symlinked $(ls "$AIBUILDER_DIR/.claude/agents/"*.md | wc -l | tr -d ' ') agents → $CLAUDE_AGENTS_DIR"

# ── Kill any existing sessions for this project ───────────────────────
tmux kill-session -t "=$CONDUCTOR_SESSION"   2>/dev/null || true
tmux kill-session -t "=$COCONDUCTOR_SESSION" 2>/dev/null || true

# ── Launch Conductor (own session, one window) ────────────────────────
echo "Launching Conductor..."
tmux new-session -d -s "$CONDUCTOR_SESSION" -x 220 -y 50
tmux send-keys -t "=$CONDUCTOR_SESSION" \
  "export PROJECT_DIR='$PROJECT_DIR' AIBUILDER_DIR='$AIBUILDER_DIR' PROJECT_NAME='$PROJECT_NAME'" Enter
sleep 1
tmux send-keys -t "=$CONDUCTOR_SESSION" \
  "cd '$PROJECT_DIR' && claude --model claude-sonnet-4-6 --dangerously-skip-permissions --agent dev-conductor" Enter
sleep 8
tmux send-keys -t "=$CONDUCTOR_SESSION" "" Enter   # absorb first-Enter quirk (boot sometimes eats it)
sleep 1

# Send initial orientation — starts the first read of STATUS.md
tmux send-keys -t "=$CONDUCTOR_SESSION" \
  "DevLoop starting for $PROJECT_NAME. Read AGENTS.md and 05-progress/STATUS.md to orient yourself, then wait for 'tick' messages from the cron scheduler." Enter

# ── Launch Co-Conductor (own session, one window) ─────────────────────
echo "Launching Co-Conductor..."
tmux new-session -d -s "$COCONDUCTOR_SESSION" -x 220 -y 50
tmux send-keys -t "=$COCONDUCTOR_SESSION" \
  "export PROJECT_DIR='$PROJECT_DIR' AIBUILDER_DIR='$AIBUILDER_DIR' PROJECT_NAME='$PROJECT_NAME'" Enter
sleep 1
tmux send-keys -t "=$COCONDUCTOR_SESSION" \
  "cd '$PROJECT_DIR' && claude --model claude-sonnet-4-6 --dangerously-skip-permissions --agent co-conductor" Enter
sleep 8
tmux send-keys -t "=$COCONDUCTOR_SESSION" "" Enter   # absorb first-Enter quirk
sleep 1

tmux send-keys -t "=$COCONDUCTOR_SESSION" \
  "Co-Conductor starting for $PROJECT_NAME. You will receive 'audit' messages every 15 minutes. On each audit, check if the Conductor is alive and making progress." Enter

# ── Install cron jobs ─────────────────────────────────────────────────
echo "Installing cron jobs..."

CRON_TAG="# devloop-${PROJECT_NAME}"

CRON_TICK="*/3 * * * * tmux send-keys -t '=${CONDUCTOR_SESSION}' 'tick' Enter ${CRON_TAG}-tick"
CRON_AUDIT="*/15 * * * * cp '${PROJECT_DIR}/05-progress/STATUS.md' '${PROJECT_DIR}/.devloop/status-snapshot.md' 2>/dev/null; tmux send-keys -t '=${COCONDUCTOR_SESSION}' 'audit' Enter ${CRON_TAG}-audit"

# Remove any existing devloop cron entries for this project
( crontab -l 2>/dev/null | grep -v "# devloop-${PROJECT_NAME}-" ) | crontab - 2>/dev/null || true

# Add the new entries
( crontab -l 2>/dev/null
  echo "$CRON_TICK"
  echo "$CRON_AUDIT"
) | crontab -

echo "Cron installed: conductor ticked every 3 min, co-conductor audited every 15 min."
echo ""
echo "================================================================"
echo "DevLoop is running."
echo ""
echo "  Conductor:      tmux attach -t $CONDUCTOR_SESSION"
echo "  Co-Conductor:   tmux attach -t $COCONDUCTOR_SESSION"
echo ""
echo "  Status:         cat '$PROJECT_DIR/05-progress/STATUS.md'"
echo "  Event log:      tail -f '$PROJECT_DIR/05-progress/devloop-event.log'"
echo "  Cron check:     crontab -l | grep devloop"
echo "  Stop:           bash '$AIBUILDER_DIR/scripts/devloop-stop.sh' '$PROJECT_DIR'"
echo "================================================================"

#!/usr/bin/env bash
# devloop-stop.sh
# Stops all DevLoop sessions and cron jobs for a project.
#
# Usage: bash /path/to/AIBuilder/scripts/devloop-stop.sh <project-dir>

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

CONDUCTOR_SESSION="conductor-${PROJECT_NAME}"
COCONDUCTOR_SESSION="coconductor-${PROJECT_NAME}"

echo "Stopping DevLoop for $PROJECT_NAME..."

# Kill agent sessions dispatched by the conductor
for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^agent-.*-${PROJECT_NAME}$"); do
  tmux kill-session -t "$session" 2>/dev/null && echo "  Killed agent session: $session" || true
done

# Kill conductor and co-conductor
tmux kill-session -t "$CONDUCTOR_SESSION"   2>/dev/null && echo "  Killed: $CONDUCTOR_SESSION"   || echo "  (not running): $CONDUCTOR_SESSION"
tmux kill-session -t "$COCONDUCTOR_SESSION" 2>/dev/null && echo "  Killed: $COCONDUCTOR_SESSION" || echo "  (not running): $COCONDUCTOR_SESSION"

# Remove cron jobs
( crontab -l 2>/dev/null | grep -v "# devloop-${PROJECT_NAME}-" ) | crontab - 2>/dev/null || true
echo "  Cron entries removed."

echo "Done."

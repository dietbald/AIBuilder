# AIBuilder Stress Tests

Tests that must pass before the system is considered operational. Run in order — each is a gate.

---

## ST-01 — PONG Test (Claude CLI PTY Behavior)

**Status:** Not yet run  
**Priority:** GATE — nothing else runs until this passes  
**Origin:** Council #2, 2026-05-04 — caught by all 5 peer reviewers as the foundational unknown

**What it tests:** Whether `claude` interactive mode behaves predictably when its stdin is a tmux pseudo-TTY rather than a real terminal. The entire `tmux send-keys` trigger mechanism depends on this being true. It is currently undocumented.

**The test:**
```bash
tmux new-session -d -s test-claude
tmux send-keys -t test-claude "claude" Enter
sleep 5
tmux send-keys -t test-claude "say the word PONG and nothing else" Enter
sleep 15
tmux capture-pane -t test-claude -p
tmux kill-session -t test-claude
```

**Pass criteria:** The captured output contains the word `PONG` cleanly, with no injection artifacts, garbled input, or empty response.

**If it fails:** Replace `tmux send-keys` as the trigger mechanism. Options:
- **File-based queue:** Conductor polls a trigger file (e.g., `.devloop/tick`) every N seconds. Cron writes the file. Conductor reads it, deletes it, acts.
- **Named pipe:** Conductor reads from a named pipe (FIFO). Cron writes to it. Clean IPC, no PTY issues.
- **`claude --resume`:** Use `claude --resume <session-id> --print "tick"` for each tick instead of interactive mode. Stateless but loses conversation history.

---

## ST-02 — Cron PATH

**Status:** Not yet run  
**Priority:** First-run blocker  
**What it tests:** Whether `tmux` is in cron's PATH when the tick/audit cron jobs fire.

**The test:**
```bash
# Add to crontab and check output after 1 minute
* * * * * which tmux >> /tmp/devloop-cron-path-test.txt 2>&1
```

**Pass criteria:** `/tmp/devloop-cron-path-test.txt` contains a valid path to tmux (e.g., `/usr/bin/tmux`).

**Fix if fails:** Add `PATH=/usr/bin:/usr/local/bin:/bin` as the first line in the crontab.

---

## ST-03 — tmux Exact-Match Session Check

**Status:** Not yet run  
**What it tests:** Whether `tmux has-session -t "=session-name"` (exact-match syntax) works correctly in the installed tmux version and prevents partial-name false positives.

**The test:**
```bash
tmux new-session -d -s "agent-dev-spec-author-F-01-BidPlatform"
# Should match (exact):
tmux has-session -t "=agent-dev-spec-author-F-01-BidPlatform" 2>/dev/null && echo "EXACT MATCH OK"
# Should NOT match (partial):
tmux has-session -t "=agent-dev-spec-author-F-01" 2>/dev/null && echo "PARTIAL MATCH (BAD)" || echo "NO PARTIAL MATCH OK"
tmux kill-session -t "agent-dev-spec-author-F-01-BidPlatform"
```

**Pass criteria:** First check prints `EXACT MATCH OK`. Second check prints `NO PARTIAL MATCH OK`.

**Fix if fails:** tmux version is older than 3.x. Either upgrade tmux or replace the has-session check with a status-file approach (see fix list from Council #2).

---

## ST-04 — Tick Deduplication (Lockfile)

**Status:** Not yet run  
**What it tests:** That a second cron tick arriving while the conductor is mid-response is correctly suppressed by the lockfile mechanism.

*(Design the lockfile mechanism first, then write this test.)*

---

## ST-05 — Conductor Restart Reconciliation

**Status:** Not yet run  
**What it tests:** That when the conductor session is killed mid-task and restarted (either by co-conductor Level 3 restart or by session rotation at tick 50), it correctly reconciles orphaned agent sessions and advances STATUS.md before taking new action.

**Session rotation is now implemented** — at tick 50 the conductor self-terminates and resets the counter. The co-conductor's Level 3 restart procedure then brings it back. This test validates that restart path end-to-end.

*(The reconciliation procedure is the co-conductor Level 3 restart already in co-conductor.md. This test verifies it works under real conditions.)*

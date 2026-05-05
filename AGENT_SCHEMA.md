# AGENT_SCHEMA.md — Agent Output Contract

Every agent in the DevLoop pipeline writes a structured schema block at the end of its output, followed by a sentinel line. The Conductor reads this block to determine what happened and what to do next.

---

## Required Schema Block Format

Every agent output file must end with:

```
---AGENT_OUTPUT---
verdict: PASS | FAIL
status: done | blocked
output_path: <repo-relative path to the primary artifact>
blocking_count: <integer — 0 if PASS>
notes: <empty if PASS; required if FAIL — specific actionable description of what went wrong>
---DEVLOOP_DONE---
```

The `---DEVLOOP_DONE---` sentinel is how the Conductor knows the agent has finished. Do not write it until your work is truly complete.

---

## Field Definitions

| Field | Required | Values |
|---|---|---|
| `verdict` | Always | `PASS` or `FAIL` |
| `status` | Always | `done` (work complete) or `blocked` (cannot continue) |
| `output_path` | Always | Repo-relative path to main artifact (e.g., `02-specs/F-03-genre-filter/spec.md`) |
| `blocking_count` | Always | Number of blocking issues found (0 on PASS) |
| `notes` | Required on FAIL | One or two sentences explaining exactly what failed and why. Must be actionable — the next attempt should be able to address this specifically. Empty string on PASS. |

---

## Invariants

1. Every agent output file ends with `---DEVLOOP_DONE---`
2. The `---AGENT_OUTPUT---` block appears immediately before the sentinel
3. All 5 fields are present — no field may be omitted
4. `notes` is **required** on FAIL — an empty `notes` on FAIL is a schema error
5. `output_path` must be a real path the next agent can read (verified to exist on PASS)
6. The sentinel must appear on its own line with no trailing characters

---

## Examples

### Successful spec author output

```
---AGENT_OUTPUT---
verdict: PASS
status: done
output_path: 02-specs/F-03-genre-filter/spec.md
blocking_count: 0
notes:
---DEVLOOP_DONE---
```

### Failed spec verifier output

```
---AGENT_OUTPUT---
verdict: FAIL
status: blocked
output_path: 05-progress/qa-reports/F-03-spec-verify-2026-05-04.md
blocking_count: 3
notes: Spec missing DB-state assertions in 2 Gherkin scenarios (Scenario 3 and 5 only assert UI, not database). Also WHAT/HOW violation on line 47 — spec describes HTTP path shape which is implementation detail.
---DEVLOOP_DONE---
```

### Failed reviewer output

```
---AGENT_OUTPUT---
verdict: FAIL
status: blocked
output_path: 05-progress/qa-reports/F-03-review-2026-05-04.md
blocking_count: 2
notes: Service layer contains Drizzle query at bid-submission.service.ts:78 — must be moved to repository. Error code at route handler line 34 uses raw string instead of ENTITY_CONDITION format.
---DEVLOOP_DONE---
```

---

## Conductor Parsing

The Conductor extracts fields using:

```bash
VERDICT=$(awk '/^---AGENT_OUTPUT---/{f=1;next} f && /^verdict:/{sub(/^verdict:[[:space:]]*/,""); print; exit}' "$OUTPUT")
STATUS=$(awk '/^---AGENT_OUTPUT---/{f=1;next} f && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' "$OUTPUT")
OUTPUT_PATH=$(awk '/^---AGENT_OUTPUT---/{f=1;next} f && /^output_path:/{sub(/^output_path:[[:space:]]*/,""); print; exit}' "$OUTPUT")
BLOCKING_COUNT=$(awk '/^---AGENT_OUTPUT---/{f=1;next} f && /^blocking_count:/{sub(/^blocking_count:[[:space:]]*/,""); print; exit}' "$OUTPUT")
NOTES=$(awk '/^---AGENT_OUTPUT---/{f=1;next} f && /^notes:/{sub(/^notes:[[:space:]]*/,""); print; exit}' "$OUTPUT")
```

---

## Integrity Check

Before parsing the schema block, the Conductor verifies the file is not a partial write:

```bash
SCHEMA_LINE=$(grep -n '^---AGENT_OUTPUT---' "$OUTPUT" 2>/dev/null | head -1 | cut -d: -f1)
SENTINEL_LINE=$(grep -n '\-\-\-DEVLOOP_DONE\-\-\-' "$OUTPUT" 2>/dev/null | tail -1 | cut -d: -f1)

if [ -z "$SCHEMA_LINE" ] || [ -z "$SENTINEL_LINE" ] || [ "$SCHEMA_LINE" -ge "$SENTINEL_LINE" ]; then
  echo "INTEGRITY FAIL — schema block missing or appears after sentinel (partial write) — re-dispatching"
  exit 1
fi
```

---

## Notes for Agent Authors

- Write the schema block as the LAST thing you do, after all work is complete
- Do not write `---DEVLOOP_DONE---` mid-task as a progress indicator
- `output_path` should point to the primary artifact the next agent needs to read
- For agents that write multiple files (implementer), `output_path` points to the primary new file; reference others in `notes` or the body
- If blocked before producing any artifact, set `output_path` to the partial artifact or the progress directory

# Council Transcript — Council #4
Date: 2026-05-04
Topic: AIBuilder system audit — post-fix consistency check and deep architectural review

---

## Original Question

AIBuilder is a multi-agent autonomous software development system. Prior audits fixed 9 issues. Seven known issues remain. Does the system design have deeper problems beyond these? Are there issues the team is missing?

**Known remaining issues (pre-council):**
1. `AskUserQuestion` in dev-spec-author.md tools doesn't exist in Claude Code
2. BrowserControl missing from dev-qa-tester.md frontmatter tools
3. Stale Codex references in implementer/test-author/reviewer descriptions
4. dev-test-author says "parallel" but pipeline is sequential
5. No dev server startup before e2e tests
6. Retry counter shared between implementing and review-retry phases (same key)
7. Fresh STATUS.md has no feature rows — conductor idles with no way to populate from FEATURES.md

---

## Advisor Responses (Advisor → Letter mapping revealed)

| Letter | Advisor |
|---|---|
| A | The Contrarian |
| B | The First Principles Thinker |
| C | The Expansionist |
| D | The Outsider |
| E | The Executor |

---

## Response A — The Contrarian

Seven distinct failure modes, ranked by severity:

1. **QA Tester is dead on arrival.** BrowserControl is not in the tools list. The agent will attempt browser automation with only Read, Write, Bash — it will fail every UI test silently or with bash errors. Every feature requiring browser verification will cycle through retries and escalate to Tier 4. This isn't a documentation bug; it's a broken agent.

2. **E2E tests run against nothing.** No dev server starts before test-authoring. `pnpm test:e2e` will connect to localhost and get connection refused. The "All tests GREEN" checklist item is structurally impossible to satisfy without a running server.

3. **Retry budget poisoning is silent and guaranteed.** A feature with two implementing failures exhausts `F-01:dev-implementer`. On review failure, the re-dispatch immediately hits MAX_RETRIES and escalates to Tier 4 — without the human understanding why. The counter conflation isn't an edge case; it's the default path for any non-trivial feature.

4. **Fresh project deadlocks silently.** Nothing populates STATUS.md after Inception runs. The Conductor logs "idle" forever. There is no trigger to read Inception's output and write feature rows. The pipeline never starts.

5. **Codex references are live stale state, not dead documentation.** The Reviewer is instructed to behave differently "if Implementer ran on Codex." Since Implementer always runs on Sonnet, the Reviewer's cross-CLI verification rationale is permanently false. Its behavior is undefined against its own stated preconditions.

6. **AskUserQuestion in unattended automation.** The Spec Author will block waiting for human input. With no human present, the 30-minute watchdog kills it. That's a retry wasted every time ambiguity exists in specs.

7. **Conductor session rotation at tick 50 with in-flight agents.** Nothing drains active agents before self-termination. Completions written while the Conductor is restarting get dropped.

---

## Response B — The First Principles Thinker

The central assumption is wrong: software development is not a pipeline.

A pipeline implies deterministic stage transitions — input goes in, output comes out, state advances. But software development is fundamentally a search problem under uncertainty. You don't know what you're building until you've partially built it. Specs reveal their own ambiguities only when implementation begins. Tests expose requirements the spec never articulated. The "pipeline" framing forces linear progression through a process that is inherently recursive.

The system treats STATUS.md as ground truth, but ground truth in software development is the *running system*, not a document. Every abstraction layer here — STATUS.md, FEATURES.md, agent prompts — is a lossy encoding of intent. Errors compound across encodings. By the time the QA agent runs, the original intent has been telephone-gamed through four agents.

Deeper: what does "autonomous" actually mean here? The system autonomously executes a human-defined pipeline. That's automation, not autonomy. Real autonomy would mean the system could recognize when the pipeline itself is wrong for this problem and adapt. This system cannot do that. It will confidently march through all eight stages producing sophisticated-looking artifacts that miss the point entirely — and no agent is positioned to catch that.

The most dangerous failure mode isn't any of the seven catalogued bugs. It's **confident wrongness at scale** — the system produces complete, coherent, passing-tests software that solves the wrong problem. There is no stage for "is this actually what we needed?"

The right question isn't "how do we fix stage transitions?" It's: "Where does human judgment re-enter the loop, and is that checkpoint load-bearing or ceremonial?"

---

## Response C — The Expansionist

The team is building a **factory**, not a tool — and they haven't realized it yet.

Right now AIBuilder produces one software project. But the architecture — file-based state, restartable agents, pipeline stages — is fundamentally a reusable manufacturing line. The moment you parameterize the FEATURES.md input and run multiple Conductor sessions in parallel, you have a software factory that can build N products simultaneously. One server, infinite products.

The bigger miss: the pipeline terminates at `done`. That's the wrong endpoint. Real software doesn't ship and stop — it accumulates users, bug reports, feature requests, and usage telemetry. The natural extension is a living system: post-deploy monitoring feeds back into FEATURES.md as new pending items, creating a closed loop. The Conductor never fully sleeps. The product evolves autonomously.

Adjacent opportunity hiding in plain sight: **spec-as-product**. The speccing and spec-verifying stages produce validated, cross-model-verified specifications. Those specs have standalone value — they could be sold, shared, or used to train smaller specialist models. The system is accidentally generating a dataset of high-quality software specifications.

Biggest undervalued asset: the **DECISIONS.md file**. Every fork in the road, every design choice the system made autonomously — that's institutional memory that compounds. If you index it and make it retrievable across projects, the system gets smarter about each new project based on every previous one. Cross-project learning. The Conductor stops starting from zero.

The 10x framing isn't "build software faster." It's **autonomous product portfolio management** — continuously speccing, building, shipping, and evolving a catalog of software products with minimal human intervention. The team is one abstraction layer away from that.

---

## Response D — The Outsider

Following the docs exactly, here is what breaks immediately.

**Before even starting:** The prerequisites list "openclaw (optional for Telegram alerts)" with zero explanation of what openclaw is, where to get it, or what "optional" means operationally. A new user either skips it and loses alerts silently, or spends time hunting for something undocumented.

**Phase 1:** The BA agent calls `AskUserQuestion`. This tool does not exist. The agent fails mid-inception. The user has no idea why — the error will look like a tool resolution failure, not a documentation problem. They will probably assume they installed something wrong.

**Phase 2:** The user runs `devloop-start.sh`. It creates a STATUS.md with empty headers. The Conductor starts, reads STATUS.md, finds nothing, and logs "idle" forever. The system appears to be running. Nothing happens. There is no error. A first-time user will sit there waiting, assuming the system is thinking.

This is the worst kind of failure: silent, plausible-looking, and pointing nowhere.

Reading the agent files to debug: The implementer docs say "Best CLI is Codex." The reviewer doc references Codex as the cross-verification partner. Codex does not exist here. A user trying to understand the architecture will build a completely wrong mental model before they have run a single feature.

The QA agent lists BrowserControl in its description but not its tools frontmatter. It silently cannot do what it claims.

The core problem: every failure in this system is silent or misdirected. Nothing tells the user where they actually are or what actually broke. The system looks like it is working right up until it is not.

---

## Response E — The Executor

Concrete fixes ordered by what kills you first on run day:

**Issue 7 — Immediate deadlock.** STATUS.md initializes with an empty table. The conductor reads it, finds no features, idles forever. Fix: after creating STATUS.md, parse FEATURES.md and append a row per feature.
```bash
grep -oE '^## (F-[0-9]+)' "$PROJECT_DIR/FEATURES.md" | sed 's/## //' | while read F; do
  echo "| $F | pending |" >> "$PROJECT_DIR/05-progress/STATUS.md"
done
```

**Issue 1 — Fails on first spec run.** `AskUserQuestion` is not a Claude Code tool. Fix: remove from `dev-spec-author.md` tools list; replace body references with "document in the `[NEEDS CLARIFICATION]` section."

**Issue 5 — Fails on first e2e run.** `pnpm test:e2e` against no server = instant crash. Fix: add server startup step in `dev-test-author.md` before running tests.

**Issue 6 — Premature Tier 4 on first review retry.** Fix: use `${FEATURE}:${ROLE}:review-retry` as the key when re-dispatching from a review failure.

**Issues 2, 3, 4 — Wrong metadata, non-fatal but misleading.** Add BrowserControl to QA Tester tools list. Replace Codex references with actual model names (`claude-sonnet-4-6` for implementer/test-author, `claude-opus-4-7` for reviewer). Update test-author description from "parallel" to "sequential."

---

## Peer Reviews

**Anonymization mapping revealed:**

| Letter during review | Advisor |
|---|---|
| A | The Contrarian |
| B | The First Principles Thinker |
| C | The Expansionist |
| D | The Outsider |
| E | The Executor |

### Reviewer 1
- **Strongest:** E (actionable, file-specific fixes with exact references)
- **Biggest blind spot:** C (product vision masquerading as technical review)
- **All missed:** Inter-agent output validation — no schema, checksum, or handshake between stages; malformed spec propagates silently through entire pipeline

### Reviewer 2
- **Strongest:** A (causal chain, specificity, explains *why* each failure occurs)
- **Biggest blind spot:** C (answers a different question entirely)
- **All missed:** Observability — no structured event log, no flight recorder; when system fails silently, there is no artifact to diagnose from

### Reviewer 3
- **Strongest:** A (systematic coverage + genuine new finding in item 7 — session rotation drops in-flight completions)
- **Biggest blind spot:** C (no failure modes identified)
- **All missed:** Idempotency — interrupted agents leave half-written files; no checksums, no atomic writes; crashed Implementer leaves corrupt artifacts that Reviewer reads without complaint

### Reviewer 4
- **Strongest:** A (specific, severity-ranked, explains causation)
- **Biggest blind spot:** C (vision not analysis)
- **All missed:** Feedback loop is write-only — agents are blind to predecessor reasoning; compounding errors invisible until human reviews post-hoc; no mid-flight correction mechanism

### Reviewer 5
- **Strongest:** A (diagnostic and specific)
- **Biggest blind spot:** C (romanticizes architecture)
- **All missed:** No recovery semantics — mid-pipeline failures leave STATUS.md, DECISIONS.md, and retry counters in indeterminate state; no rollback, no checkpoint; system fails forward into garbage state that next run inherits

---

## Chairman's Verdict

### Where the Council Agrees

**The system fails silently.** Every advisor independently arrived at this conclusion from a different angle. The Contrarian catalogued seven specific silent failures. The Outsider named it as the core finding. The Executor wrote fixes for it. The First Principles Thinker called it "confident wrongness at scale." No advisor found a counter-example. This is the highest-confidence signal the council produced: when AIBuilder breaks, nothing tells you — not the user, not the logs, not the STATUS.md, not the agents themselves. The system produces silence or continued execution as its failure signal, which is indistinguishable from success.

**The Contrarian's specific bugs are real.** All five reviewers ranked Response A as the strongest. The bugs named — BrowserControl absent from frontmatter, AskUserQuestion nonexistent, empty STATUS.md causing conductor idle, retry key collision, no dev server before e2e — were not challenged on accuracy by any reviewer. They were only criticized for scope (not going far enough). This means the seven failure modes should be treated as confirmed, not as allegations.

**The Codex documentation is actively harmful.** Multiple advisors noted that stale references to Codex mislead both agents and developers. This is worse than missing documentation — it creates false confidence in preconditions that are permanently false.

### Where the Council Clashes

**Is this a pipeline problem or a search problem?**

The First Principles Thinker argues the linear pipeline framing is the root cause — software development is recursive and uncertain, and forcing it into sequential stages produces the wrong architecture. The Executor implicitly rejects this: given the system as built, fix the specific bugs and it works. These are not reconcilable positions. One says the architecture is wrong at the conceptual level; the other says the implementation has fixable defects.

The council cannot resolve this without a clearer statement of what "success" means for AIBuilder. If success means "autonomously ships working features for known problem domains," the Executor is right — fix the bugs, the pipeline works. If success means "handles novel, ambiguous, or evolving requirements without human intervention," the First Principles Thinker is right — the pipeline architecture will keep producing confident wrong output that passes its own tests.

**Is the Expansionist's vision a finding or a distraction?**

All five reviewers called Response C the biggest blind spot. The Expansionist reframed the system as a product portfolio manager and argued for post-deploy feedback loops and cross-project learning. Reviewers unanimously judged this as vision masquerading as technical analysis. The Expansionist is not wrong that the system's multi-conductor architecture implies portfolio management potential. But that potential is irrelevant when the system deadlocks on an empty STATUS.md before it runs a single feature.

### Blind Spots the Council Caught

**No inter-agent validation.** No schema, checksum, or handshake between pipeline stages. A malformed spec propagates silently through Implementer, Reviewer, and QA Tester without any stage rejecting it. File presence is treated as correctness.

**No observability infrastructure.** No structured event log, no flight recorder. When the system fails — silently, repeatedly — there is no artifact recording what happened. Post-mortem is impossible.

**No idempotency or atomic writes.** An interrupted agent leaves a half-written file. The next stage reads that file without complaint. No checksums, no write-acknowledgment, no atomic file operations. A crashed agent corrupts its artifact, and the system inherits that corruption silently.

**No recovery semantics.** Mid-pipeline failures leave STATUS.md, DECISIONS.md, and retry counters in indeterminate state. No rollback mechanism, no checkpoint. The next run inherits garbage state from the previous failed run with no way to detect or discard it.

**Write-only feedback loop.** Each agent writes output but does not read predecessor reasoning. Compounding errors are invisible because no agent has visibility into the reasoning of the stage before it — only its file output.

### The Recommendation

Do not deploy AIBuilder on any production feature until the five architectural gaps from peer review are addressed alongside the seven implementation bugs.

The Executor's fixes are correct and should be executed first. Then add observability before running any real workload — a structured event log is not optional; it is the minimum prerequisite for trusting any output the system produces. Then address atomic writes and recovery semantics.

The pipeline architecture is not wrong in principle for the problem domain. But it is missing the infrastructure that makes autonomous systems trustworthy: the ability to detect its own failures, record what happened, refuse corrupt inputs, and recover to a known-good state.

### The One Thing to Do First

Add a structured event log — a single append-only file that every agent, conductor, and cron job writes to with a timestamp, agent role, feature ID, and status on every state transition.

This is first because it unlocks everything else. Without it, you cannot confirm the Executor's fixes worked. You cannot detect the retry key collision. You cannot see the STATUS.md deadlock happening. You cannot distinguish a silent success from a silent failure. Every failure mode identified by the entire council — all twelve of them — becomes diagnosable once this exists.

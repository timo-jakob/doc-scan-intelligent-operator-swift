---
description: Run the Swift code reviewer on all recent changes
argument-hint: "[optional: specific file or directory to review]"
---

## Swift Code Review — Parallel Agent Orchestrator

Run 6 specialized review agents in parallel for comprehensive Swift code review.

### Step 1: Determine Review Scope

Determine which Swift files to review:
- If a specific path was provided as argument, review only that path
- Otherwise, run `git diff --name-only -- '*.swift'` and `git diff --staged --name-only -- '*.swift'`
- If no git changes are found, review all Swift files in `Sources/`

Store the file list — you'll pass it to every agent.

### Step 2: Launch All 6 Agents in Parallel

Launch all 6 agents simultaneously using the **Task tool**. Each agent gets the same file list.
Use a **single message** with 6 Task tool calls to ensure true parallelism.

The agents and their `subagent_type` values:

| Agent | subagent_type | Model | Focus |
|-------|--------------|-------|-------|
| Bug Hunter | `bug-hunter` | opus | Bugs, logic errors, crashes, stability |
| Security Reviewer | `security-reviewer` | sonnet | Vulnerabilities, injection, secrets |
| Performance Reviewer | `performance-reviewer` | sonnet | Allocations, complexity, retain cycles |
| Swift 6 Compliance | `swift6-compliance` | sonnet | Strict concurrency, typed throws, modern syntax |
| Code Quality | `code-quality` | sonnet | Naming, structure, readability |
| Test Reviewer | `test-reviewer` | sonnet | Coverage, test quality, spec conformance |

For each agent, the prompt should be:
```
Review the following Swift files for {agent's focus area}: {file list}
```

### Step 3: Collect and Present Results

After all 6 agents return, present a unified report:

```
============================================================
  SWIFT CODE REVIEW — UNIFIED REPORT
============================================================

{Bug Hunter results}

{Security Reviewer results}

{Performance Reviewer results}

{Swift 6 Compliance results}

{Code Quality results}

{Test Reviewer results}

============================================================
  SUMMARY
============================================================
- Total findings: N critical, N warnings, N suggestions
- Agents that found issues: (list)
- Agents with clean results: (list)
```

### Step 4: Fix Issues

- **Automatically fix** all Critical issues found by any agent
- **Automatically fix** all Warning issues found by any agent
- **List** remaining Suggestions for the developer to decide on

**Conflict prevention**: Multiple agents may flag the same file for different reasons. Apply fixes
one agent at a time, re-reading the file between each agent's fixes to avoid clobbering earlier
changes. Recommended order (highest-impact first):

1. Bug Hunter (correctness fixes may change code that other agents also flagged)
2. Security Reviewer
3. Performance Reviewer
4. Swift 6 Compliance
5. Code Quality

If two agents propose conflicting changes to the same code, the higher-priority agent wins.

### Step 5: Commit

Use **separate commits** to keep code fixes and test additions reviewable independently:

1. **Code fixes first** — stage and commit all source code fixes (from bug-hunter, security, performance, swift6, code-quality agents) via `/commit-and-push`
2. **Test additions second** — stage and commit new/modified test files (from test-reviewer) via `/commit-and-push`

If only one category has changes, a single commit is fine.

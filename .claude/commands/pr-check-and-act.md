---
description: Fetch feedback from all GitHub Actions checks on a PR and automatically fix every actionable issue
argument-hint: PR number (e.g. 33)
allowed-tools: Bash(gh *), Bash(make *), Bash(swift *), Bash(git *), Bash(curl *), Read, Edit, Write, Glob, Grep, Task
---

You are reviewing Pull Request #$ARGUMENTS on GitHub. Your job is to fetch all CI feedback, fix every actionable issue, and commit the fixes.

> **How `$ARGUMENTS` works:** `$ARGUMENTS` is substituted into this prompt text before any shell runs. If the user supplies no argument, it becomes an empty string; if they supply `34`, the shell sees the literal `34`. The `argument-hint` frontmatter (`PR number (e.g. 33)`) prompts the user for input when they forget to supply one.

**Iteration limit: stop after 3 commit cycles.** If failing checks remain after the third attempt, surface them to the user and stop.

## Step 1: Get the PR overview and switch to the PR branch

Validate the argument, then fetch PR metadata:

```bash
if ! [[ "$ARGUMENTS" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be a positive integer. Usage: /pr-check-and-act <PR_NUMBER>"
  exit 1
fi

gh pr view $ARGUMENTS --json title,url,headRefName,baseRefName
gh pr checks $ARGUMENTS
```

Print the PR title, branch, and a summary table of which checks passed and which failed/have comments.

**Switch to the PR branch before doing anything else** — if the local branch differs from the PR head, all file edits would land on the wrong branch:

```bash
git switch <headRefName from gh pr view above>
```

Capture the values needed by the sub-agents (substitute the real values into every agent prompt before dispatching — agents do not inherit parent shell state):

```bash
BRANCH=$(gh pr view $ARGUMENTS --json headRefName -q .headRefName)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# Derive SonarCloud project key from repo slug (owner/name → owner_name)
REPO_KEY=$(gh repo view --json nameWithOwner -q '.nameWithOwner | gsub("/"; "_")')
```

## Step 2: Fetch detailed feedback — all 4 checks in parallel

Use the Task tool to launch all four agents simultaneously in a **single message** (one tool call block with four Task invocations). Each agent uses `subagent_type=Bash`.

**Before dispatching**, substitute the real values of `BRANCH`, `REPO`, `REPO_KEY`, and the PR number into each agent's prompt. Do not leave placeholders like `<branch from step 1>` in the prompts.

---

**Agent 1 — CI / Code Quality**

`gh run list` returns workflow-level run names, not job names. The workflow is named `CI`; `Code Quality` is a job inside it and will never appear as a run name. Filter on `CI` only.

Lint steps have `continue-on-error: true` in CI, so the job always exits 0 regardless of violations. Do **not** use `--log-failed` — fetch full logs and grep for violation markers instead.

```bash
BRANCH="<real branch name from step 1>"

# Find the most recent CI workflow run for this branch
RUN_ID=$(gh run list --branch "$BRANCH" --json databaseId,name,conclusion,status \
  --jq '.[] | select(.name == "CI") | .databaseId' | head -1)

if [ -z "$RUN_ID" ]; then
  echo "No CI run found for branch $BRANCH"
  exit 0
fi

# Fetch full logs (not --log-failed) to capture lint violations hidden by continue-on-error
# Tight pattern to avoid matching log noise (URLs, progress descriptions, etc.)
gh run view "$RUN_ID" --log | grep -E "\.(swift|md):[0-9]+:[0-9]+: (warning|error):|\*\* BUILD FAILED \*\*|^error: " | head -100
```

Return: a structured list of build errors, test failures, and lint violations — each with file path and line number where available.

---

**Agent 2 — Snyk Security Analysis**

> ⚠️ Snyk only runs on pushes to `main` in this repo, not on PR branches. This agent will almost always return NO DATA for feature branches. Report this explicitly rather than silently returning "no vulnerabilities".

```bash
BRANCH="<real branch name from step 1>"

RUN_ID=$(gh run list --branch "$BRANCH" --json databaseId,name,conclusion,status \
  --jq '.[] | select(.name | ascii_downcase | contains("snyk")) | .databaseId' | head -1)

if [ -z "$RUN_ID" ]; then
  echo "NO DATA — Snyk only runs on pushes to main, not on PR branches."
  exit 0
fi

gh run view "$RUN_ID" --log-failed
```

Return: list of vulnerabilities — package name, severity (critical/high/medium/low), CVE if present, and the remediation (which version to upgrade to). Or "NO DATA — Snyk only runs on main" if no run exists.

---

**Agent 3 — Claude Code Review**

```bash
REPO="<real repo nameWithOwner from step 1>"
PR_NUMBER="<real PR number from $ARGUMENTS>"

# Inline code review comments (on specific lines):
gh api repos/$REPO/pulls/$PR_NUMBER/comments \
  --jq '[.[] | {path: .path, line: (.line // .original_line // .start_line), side: .side, body: .body}]'

# PR-level reviews and issue thread comments (Claude posts here):
# Fetch all bot comments across all review rounds — earlier rounds may contain unresolved CLEAR suggestions
gh api repos/$REPO/issues/$PR_NUMBER/comments \
  --jq '[.[] | select(.user.login | test("claude|bot")) | {user: .user.login, body: .body, created_at: .created_at}] | sort_by(.created_at) | reverse'
```

For each comment, classify it as:
- **CLEAR** — unambiguous, actionable improvement (rename, remove dead code, fix a specific bug)
- **AMBIGUOUS** — requires judgement or design decisions

Return: two labelled lists (CLEAR / AMBIGUOUS) with file, line, and suggestion text.

---

**Agent 4 — SonarQube Analysis**

> ⚠️ SonarQube only runs on pushes to `main` in this repo, not on PR branches. The GitHub Action will almost always return NO DATA for feature branches. Query SonarCloud directly for the branch analysis when available.

Always query SonarCloud directly for open issues — **do not rely solely on the GitHub Action status or quality gate result**. A passing quality gate does not mean there are no issues; Code Smells and other findings may exist below the gate threshold.

```bash
REPO_KEY="<real repo key from step 1, e.g. owner_reponame>"
PR_NUMBER="<real PR number>"
BRANCH="<real branch name from step 1>"

# Read SonarCloud token from macOS Keychain (same source as make sonar)
SONAR_TOKEN=$(security find-generic-password -a sonar -s sonar-doc-scan-intelligent-operator-swift -w 2>/dev/null)
if [ -z "$SONAR_TOKEN" ]; then
  echo "NO DATA — SONAR_TOKEN not found in Keychain. Run: security add-generic-password -a sonar -s sonar-doc-scan-intelligent-operator-swift -w YOUR_TOKEN"
  exit 0
fi

# 1. Fetch ALL open issues for the PR analysis
PR_ISSUES=$(curl -s -u "$SONAR_TOKEN:" "https://sonarcloud.io/api/issues/search?projectKeys=$REPO_KEY&pullRequest=$PR_NUMBER&statuses=OPEN&ps=100")
PR_ISSUE_COUNT=$(echo "$PR_ISSUES" | jq '.issues | length')

if [ "$PR_ISSUE_COUNT" -gt 0 ] 2>/dev/null; then
  # PR analysis is available — use it exclusively
  echo "$PR_ISSUES" | jq '[.issues[] | {type: .type, severity: .severity, message: .message, component: .component, line: .line, rule: .rule}]'

  # Quality gate status (informational only — does NOT determine whether to fix)
  curl -s -u "$SONAR_TOKEN:" "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$REPO_KEY&pullRequest=$PR_NUMBER" | \
    jq '{gate: .projectStatus.status, conditions: .projectStatus.conditions}'
else
  # PR analysis returned no issues — fall back to branch analysis to avoid silently missing stale findings
  echo "PR analysis returned no issues; falling back to branch analysis for $BRANCH"

  BRANCH_ISSUES=$(curl -s -u "$SONAR_TOKEN:" "https://sonarcloud.io/api/issues/search?projectKeys=$REPO_KEY&branch=$BRANCH&statuses=OPEN&ps=100")
  echo "$BRANCH_ISSUES" | jq '[.issues[] | {type: .type, severity: .severity, message: .message, component: .component, line: .line, rule: .rule}]'

  curl -s -u "$SONAR_TOKEN:" "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$REPO_KEY&branch=$BRANCH" | \
    jq '{gate: .projectStatus.status}'
fi
```

Return: quality gate status (for information only) + full list of ALL open issues grouped by type — BUG, VULNERABILITY, CODE_SMELL, SECURITY_HOTSPOT — each with component path, line, severity, and message. Return "NO DATA — SonarQube only runs on main pushes" if both API calls return empty results.

---

## Step 3: Consolidated report

After all 4 agents return, print a clear summary:

```
── CI / Code Quality ─────────────────────── [PASS/FAIL]
   <error list or "all checks passed">

── Snyk Security Analysis ────────────────── [PASS/FAIL/NO DATA — main only]
   <vulnerability list or explanation>

── Claude Code Review ────────────────────── [n comments]
   CLEAR  (n): <file>:<line> — <one-line summary>
   AMBIGUOUS (n): <file>:<line> — <one-line summary>

── SonarQube Analysis ────────────────────── [gate: PASSED/FAILED/NO DATA — main only]
   BUG (n), VULNERABILITY (n), CODE_SMELL (n), SECURITY_HOTSPOT (n)
   <list of issues — shown even when gate passed>
```

## Step 4: Fix all actionable issues

Fix in this priority order:

1. **CI / Code Quality failures**
   - Build errors: diagnose and fix root cause in source files
   - Test failures: fix the failing code (not the tests, unless tests are wrong)
   - Lint/format violations:
     ```bash
     make format
     make lint
     ```
     Then fix any remaining errors reported by lint.

2. **Snyk vulnerabilities**
   - Update the affected dependency to the patched version in `Package.swift`
   - Run `swift package update` to resolve

3. **CLEAR code review suggestions**
   - Apply each CLEAR suggestion directly to the relevant source file
   - If two suggestions conflict with each other, apply neither and flag both for the user

4. **AMBIGUOUS suggestions — do NOT auto-apply**
   - List them at the end of the session for the user to decide

5. **SonarQube findings** — treat ALL open issues as mandatory fixes, regardless of whether the quality gate passed
   - **BUG**: fix immediately
   - **VULNERABILITY**: fix immediately
   - **CODE_SMELL**: fix all of them — a passing quality gate does not make them acceptable
   - **SECURITY_HOTSPOT**: review each one; fix if it represents a real risk, otherwise document why it is a false positive

## Step 5: Commit the fixes

After all changes are made, run `make format` then `make lint`, then commit inline (do **not** invoke the prepare-commit skill — it asks for user approval of the commit message, which interrupts the remediation loop):

```bash
make format
make lint  # fix any errors; re-run to confirm clean state
git add <only the changed files — never git add -A or git add .>
git status  # verify what is staged
git commit -m "$(cat <<'EOF'
fix(ci): <describe all fixes applied, e.g. resolve failing tests, apply code review suggestions>

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

> **User interaction expected here.** After each commit, show the user what was fixed (Step 6 report) and ask them to push and re-trigger CI before starting the next iteration. The user must approve continuing to the next iteration.

Do **not** push automatically.

## Step 6: Final report

Print:
- **Attempt N of 3 complete** — always state the current attempt number explicitly so the user knows when the limit is approaching
- ✅ What was fixed and committed
- ⚠️  What was flagged as ambiguous (with the original suggestion text, so the user can decide)
- ℹ️  Any checks that were already passing or returned no data (with reason)
- ℹ️  Reminder that Snyk and SonarQube only run on `main` — their results on PR branches are not available
- That the branch is ready to push when the user is satisfied

**If this was attempt 3 and checks still fail, explicitly list which checks are still failing and why, and tell the user the iteration limit has been reached.**

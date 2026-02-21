---
description: Fetch feedback from all GitHub Actions checks on a PR and automatically fix every actionable issue
argument-hint: PR number (e.g. 33)
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Task
---

You are reviewing Pull Request #$ARGUMENTS on GitHub. Your job is to fetch all CI feedback, fix every actionable issue, and commit the fixes.

## Step 1: Get the PR overview

```bash
gh pr view $ARGUMENTS --json title,url,headRefName,baseRefName
gh pr checks $ARGUMENTS
```

Print the PR title, branch, and a summary table of which checks passed and which failed/have comments.

Get the branch name for scoping workflow runs:

```bash
BRANCH=$(gh pr view $ARGUMENTS --json headRefName -q .headRefName)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## Step 2: Fetch detailed feedback — all 4 checks in parallel

Use the Task tool to launch all four agents simultaneously in a **single message** (one tool call block with four Task invocations). Each agent uses `subagent_type=Bash`.

---

**Agent 1 — CI / Code Quality**

Fetch run IDs for CI and Code Quality workflows on this branch, then get logs for any that failed:

```bash
BRANCH="<branch from step 1>"
gh run list --branch "$BRANCH" --json databaseId,name,conclusion,status \
  --jq '.[] | select(.name == "CI" or .name == "Code Quality")'

# For each failed run ID:
gh run view <RUN_ID> --log-failed
```

Return: a structured list of build errors, test failures, and lint violations — each with file path and line number where available.

---

**Agent 2 — Snyk Security Analysis**

```bash
BRANCH="<branch from step 1>"
gh run list --branch "$BRANCH" --json databaseId,name,conclusion,status \
  --jq '.[] | select(.name | ascii_downcase | contains("snyk"))'

# For each failed run ID:
gh run view <RUN_ID> --log-failed
```

Return: list of vulnerabilities — package name, severity (critical/high/medium/low), CVE if present, and the remediation (which version to upgrade to).

---

**Agent 3 — Claude Code Review**

```bash
REPO="<repo from step 1>"
# Inline code review comments (on specific lines):
gh api repos/$REPO/pulls/$ARGUMENTS/comments \
  --jq '[.[] | {path: .path, line: .line, body: .body}]'

# PR-level reviews (approve / request changes with a body):
gh api repos/$REPO/pulls/$ARGUMENTS/reviews \
  --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .body != "") | {state: .state, body: .body}]'
```

For each comment, classify it as:
- **CLEAR** — unambiguous, actionable improvement (rename, remove dead code, fix a specific bug)
- **AMBIGUOUS** — requires judgement or design decisions

Return: two labelled lists (CLEAR / AMBIGUOUS) with file, line, and suggestion text.

---

**Agent 4 — SonarQube Analysis**

SonarQube runs on pushes to `main` in this repo, not on PRs. Always query SonarCloud directly for open issues — **do not rely solely on the GitHub Action status or quality gate result**. A passing quality gate does not mean there are no issues; Code Smells and other findings may exist below the gate threshold.

```bash
REPO_KEY="timo-jakob_doc-scan-intelligent-operator-swift"
PR="$ARGUMENTS"
BRANCH="<branch from step 1>"

# 1. Quality gate status (informational only — does NOT determine whether to fix)
curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$REPO_KEY&pullRequest=$PR" | \
  jq '{gate: .projectStatus.status, conditions: .projectStatus.conditions}'

# If the PR analysis is not available, fall back to the branch analysis:
curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$REPO_KEY&branch=$BRANCH" | \
  jq '{gate: .projectStatus.status}'

# 2. Fetch ALL open issues — bugs, vulnerabilities, code smells, security hotspots
curl -s "https://sonarcloud.io/api/issues/search?projectKeys=$REPO_KEY&pullRequest=$PR&statuses=OPEN&ps=100" | \
  jq '[.issues[] | {type: .type, severity: .severity, message: .message, component: .component, line: .line, rule: .rule}]'

# Fallback to branch if PR analysis not found:
curl -s "https://sonarcloud.io/api/issues/search?projectKeys=$REPO_KEY&branch=$BRANCH&statuses=OPEN&ps=100" | \
  jq '[.issues[] | {type: .type, severity: .severity, message: .message, component: .component, line: .line, rule: .rule}]'
```

Return: quality gate status (for information only) + full list of ALL open issues grouped by type — BUG, VULNERABILITY, CODE_SMELL, SECURITY_HOTSPOT — each with component path, line, severity, and message. Return "SonarCloud returned no analysis for this PR or branch" only if both API calls return empty results.

---

## Step 3: Consolidated report

After all 4 agents return, print a clear summary:

```
── CI / Code Quality ─────────────────────── [PASS/FAIL]
   <error or "all checks passed">

── Snyk Security Analysis ────────────────── [PASS/FAIL]
   <vulnerability list or "no issues">

── Claude Code Review ────────────────────── [n comments]
   CLEAR  (n): <file>:<line> — <one-line summary>
   AMBIGUOUS (n): <file>:<line> — <one-line summary>

── SonarQube Analysis ────────────────────── [gate: PASSED/FAILED/NO DATA]
   BUG (n), VULNERABILITY (n), CODE_SMELL (n), SECURITY_HOTSPOT (n)
   <list of issues — shown even when gate passed>
```

## Step 4: Fix all actionable issues

Fix in this priority order:

1. **CI / Code Quality failures**
   - Build errors: diagnose and fix root cause in source files
   - Test failures: fix the failing code (not the tests, unless tests are wrong)
   - Lint/format violations: run `make format && make lint`, then fix any remaining errors

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

After all changes are made, use the **prepare-commit** skill to:
- Ensure the branch is correct (not main)
- Run `make format` then `make lint`
- Generate a Conventional Commit message that describes all the fixes applied, e.g.:
  `fix(ci): resolve failing tests, apply code review suggestions`
- Stage only the changed files and commit

Do **not** push automatically.

## Step 6: Final report

Print:
- ✅ What was fixed and committed
- ⚠️  What was flagged as ambiguous (with the original suggestion text, so the user can decide)
- ℹ️  Any checks that were already passing
- That the branch is ready to push when the user is satisfied

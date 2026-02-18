---
name: git-github
description: Handles all git and GitHub workflow actions for this project. Use when the user says "push this to GitHub", "create a PR", "commit this", "let's push", "open a pull request", "create a branch", or "we can push this". Enforces branch-based workflow — never commits directly to main. Runs SwiftFormat, SwiftLint, and SonarQube locally before pushing. After opening a PR, waits for all CI checks and fixes any reported issues.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 2.0.0
  category: workflow
---

# Git & GitHub Workflow

## Rules — always follow these

1. **Never commit directly to `main`** — all changes go through a branch and Pull Request
2. **Use `git switch`** to change branches — never `git checkout`
3. **Format with SwiftFormat before every commit** — run `make format`
4. **Lint with SwiftLint before every commit** — fix all warnings before staging
5. **Run SonarQube locally before every push** — push only when analysis is clean
6. **Every commit must have a meaningful message** following the Conventional Commits format
7. **Include the co-authorship footer** in every commit message

---

## Instructions

### Step 1: Determine the branch name

Choose the prefix based on the nature of the change:

| Prefix | Use for |
|---|---|
| `feature/` | New functionality or capabilities |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring without behaviour change |
| `test/` | Adding or updating tests |
| `docs/` | Documentation only |
| `chore/` | Build system, dependencies, tooling, CI |
| `perf/` | Performance improvements |

Branch name format: `<prefix>/<short-description-in-kebab-case>`

Examples:
- `feature/add-contract-document-type`
- `fix/pdf-text-extraction-encoding`
- `refactor/extract-ocr-engine-protocol`
- `chore/update-mlx-swift-lm-dependency`

### Step 2: Create and switch to the branch

Check the current branch first:

```bash
git status
```

If on `main`, create the new branch:

```bash
git switch -c <branch-name>
```

If the branch already exists locally:

```bash
git switch <branch-name>
```

### Step 3: Format, lint, then stage and commit

Before staging, always format and lint the code:

```bash
# Format code with SwiftFormat
make format

# Lint with SwiftLint — fix all warnings before proceeding
make lint
```

If SwiftLint reports any warnings or errors, fix them now. Do not commit with outstanding lint issues.

Stage specific files — never use `git add .` or `git add -A` to avoid accidentally including build artifacts or credentials:

```bash
git add <file1> <file2> ...
git status  # verify what is staged
```

Write the commit message using Conventional Commits format:

```
<type>(<optional scope>): <short summary in present tense, lowercase>

<optional body — explain WHY, not what>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Good commit message examples:
- `feat(ocr): add keyword detection for prescription documents`
- `fix(pdf): handle encrypted PDFs without crashing`
- `refactor(detector): extract categorization into separate method`
- `chore(deps): update mlx-swift-lm to 2.30.0`
- `test(string-utils): add edge cases for doctor name sanitization`

Bad commit messages (never use):
- `fix stuff`
- `WIP`
- `changes`
- `update`

### Step 4: Run SonarQube locally

Before pushing, run the full SonarQube analysis locally. This builds the project, runs tests with coverage, and sends results to SonarCloud — catching issues before they ever reach GitHub.

```bash
make sonar
```

This will:
1. Build and run tests with code coverage (`xcodebuild`)
2. Convert coverage to SonarQube format
3. Generate a SwiftLint JSON report
4. Send everything to SonarCloud and wait for analysis

When it completes, it prints the SonarCloud URL. Open it and check for:

| Issue type | What to do |
|---|---|
| **Code Smells** | Refactor the flagged code — complexity, duplication, naming, etc. |
| **Security Hotspots** | Review each one; fix if it represents a real risk |
| **Bugs** | Fix immediately — these are definite defects |
| **Vulnerabilities** | Fix immediately |
| **Coverage below threshold** | Add tests for the uncovered code paths |

If issues are found: fix them, run `make format && make lint` again, stage the fixes, add a new commit, then re-run `make sonar`. Repeat until the analysis is clean.

Only push when SonarCloud shows zero new issues.

### Step 5: Push the branch

First push sets the upstream tracking:

```bash
git push -u origin <branch-name>
```

Subsequent pushes on the same branch:

```bash
git push
```

### Step 6: Open a Pull Request

```bash
gh pr create --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
- <what changed and why>

## Test plan
- [ ] `make test` passes
- [ ] `make sonar` passes with zero new issues
- [ ] Tested manually with a real document
- [ ] No regressions in existing document types

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

PR title follows the same Conventional Commits format as the commit message.

### Step 7: Wait for CI and fix all issues

After the PR is open, wait for all GitHub Actions to complete:

```bash
gh pr checks <PR-NUMBER> --watch
```

Once done, review the final status:

```bash
gh pr checks <PR-NUMBER>
```

Current CI checks on PRs:
- **Build and Test** — xcodebuild + swift test
- **Code Quality** — static analysis
- **Snyk Security Scan** — dependency vulnerability scan
- **claude-review** — AI code review

SonarQube does **not** run on PRs — it runs only on pushes to `main` as a final audit after merge. You already ran `make sonar` locally before pushing, so no surprises.

If any check fails, fix the reported issues, commit, push, and wait for the next CI run. Apply a hard limit of **10 fix commits** — if issues remain after that, stop and report to the user which checks are still failing and why.

When all checks pass, inform the user that the PR is clean and ready for review.

---

## Setup: SONAR_TOKEN in macOS Keychain

`make sonar` reads the SonarCloud token from the macOS Keychain — never from a plaintext file or environment variable. The keychain entry is named after this project so multiple projects can each have their own token. Store it once:

```bash
security add-generic-password -a sonar -s sonar-doc-scan-intelligent-operator-swift -w YOUR_TOKEN
```

Replace `YOUR_TOKEN` with your token from [SonarCloud → Account → Security](https://sonarcloud.io/account/security).

macOS will prompt for your login password. When `make sonar` later retrieves it, grant "Always Allow" to Terminal so it never prompts again.

To verify the token is stored:

```bash
security find-generic-password -a sonar -s sonar-doc-scan-intelligent-operator-swift -w
```

---

## Examples

**Example 1: User says "we can push this to GitHub"**

Actions:
1. Run `git status` to see what changed and confirm we are not on `main`
2. Determine the change type from context — ask if unclear
3. `git switch -c fix/resolve-date-extraction` (or appropriate branch)
4. Run `make format` to format all code
5. Run `make lint` and fix any warnings
6. Stage specific changed files
7. Commit with a meaningful message including the co-authorship footer
8. Run `make sonar` — wait for SonarCloud result, fix any issues
9. `git push -u origin <branch-name>`
10. `gh pr create ...`
11. `gh pr checks <PR-NUMBER> --watch` — wait for all CI checks
12. Fix any remaining CI failures; repeat until all checks are green or 10-commit limit reached

**Example 2: User says "commit this refactoring"**

Actions:
1. Confirm current branch — create one if on `main`
2. Run `make format` to format all code
3. Run `make lint` and fix any warnings
4. Stage only the refactored files
5. Commit: `refactor(detector): simplify two-phase categorization logic`
6. Run `make sonar` and fix any issues
7. Push and offer to open a PR

---

## Troubleshooting

**Accidentally on `main` before committing**

```bash
git switch -c <correct-branch-name>
# staged changes move with you automatically if not yet committed
```

**Accidentally committed to `main`**

```bash
# Move the commit to a new branch without losing work
git switch -c <correct-branch-name>
git switch main
git reset --hard origin/main
```

**Push rejected (remote has new commits)**

```bash
git pull --rebase origin <branch-name>
git push
```

**PR already exists for this branch**

```bash
gh pr view  # check existing PR
gh pr edit  # update title or body if needed
```

**`make sonar` fails: SONAR_TOKEN not found**

```bash
security add-generic-password -a sonar -s sonar-doc-scan-intelligent-operator-swift -w YOUR_TOKEN
```

**`make sonar` fails: keychain access prompt keeps appearing**

In the macOS Keychain access dialog, click "Always Allow" for Terminal (or your shell). This grants permanent access without repeated prompts.

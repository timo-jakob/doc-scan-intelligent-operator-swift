---
name: git-github
description: Handles all git and GitHub workflow actions for this project. Use when the user says "push this to GitHub", "create a PR", "commit this", "let's push", "open a pull request", "create a branch", or "we can push this". Enforces branch-based workflow — never commits directly to main. After opening a PR, waits for all CI checks including SonarQube and fixes any reported issues.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 1.1.0
  category: workflow
---

# Git & GitHub Workflow

## Rules — always follow these

1. **Never commit directly to `main`** — all changes go through a branch and Pull Request
2. **Use `git switch`** to change branches — never `git checkout`
3. **Every commit must have a meaningful message** following the Conventional Commits format
4. **Include the co-authorship footer** in every commit message

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

### Step 3: Stage and commit

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

### Step 4: Push the branch

First push sets the upstream tracking:

```bash
git push -u origin <branch-name>
```

Subsequent pushes on the same branch:

```bash
git push
```

### Step 5: Open a Pull Request

```bash
gh pr create --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
- <what changed and why>

## Test plan
- [ ] `make test` passes
- [ ] Tested manually with a real document
- [ ] No regressions in existing document types

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

PR title follows the same Conventional Commits format as the commit message.

### Step 6: Wait for CI and fix all issues

After the PR is open, wait for all GitHub Actions to complete and fix every reported issue before the PR is considered ready. Apply the following loop with a hard limit of **10 fix commits**.

#### 6a — Wait for checks to finish

```bash
gh pr checks <PR-NUMBER> --watch
```

This blocks until all checks complete. Once done, review the final status:

```bash
gh pr checks <PR-NUMBER>
```

#### 6b — Inspect SonarQube results

If the SonarQube Cloud check failed or reported issues, fetch the details:

```bash
gh pr checks <PR-NUMBER> | grep -i sonar
```

Then read the SonarQube analysis URL from the check output and fetch its findings. Issues to look for and fix:

| Issue type | What to do |
|---|---|
| **Code Smells** | Refactor the flagged code — complexity, duplication, naming, etc. |
| **Security Hotspots** | Review each one; fix if it represents a real risk |
| **Bugs** | Fix immediately — these are definite defects |
| **Vulnerabilities** | Fix immediately |
| **Coverage below threshold** | Add tests for the uncovered code paths |

#### 6c — Fix, commit, push — repeat

For each round of fixes:

1. Fix the reported issues in the source files
2. Run `make test` locally to confirm nothing is broken
3. Stage only the changed files:
   ```bash
   git add <changed-files>
   git status
   ```
4. Commit with a descriptive message referencing the issue type:
   ```
   fix(sonar): resolve code smell in DocumentDetector complexity
   fix(sonar): address security hotspot in file path handling
   test(coverage): add missing tests for TextLLMManager error paths
   ```
5. Push:
   ```bash
   git push
   ```
6. Go back to Step 6a and wait for the next CI run

#### 6d — Timeout after 10 fix commits

Keep a mental count of fix commits made after the PR was opened. If issues are still present after **10 fix commits**, stop and report to the user:

- Which checks are still failing
- What issues remain unresolved and why
- Whether manual intervention is needed (e.g. a SonarQube false positive to suppress, a test requiring real infrastructure)

Do not continue pushing blindly — surface the blocker and ask for guidance.

#### 6e — All checks green

When `gh pr checks <PR-NUMBER>` shows all checks passing with no SonarQube issues:

```bash
gh pr checks <PR-NUMBER>
# All green — PR is ready for review
```

Inform the user that the PR is clean and ready.

---

## Examples

**Example 1: User says "we can push this to GitHub"**

Actions:
1. Run `git status` to see what changed and confirm we are not on `main`
2. Determine the change type from context — ask if unclear
3. `git switch -c fix/resolve-date-extraction` (or appropriate branch)
4. Stage specific changed files
5. Commit with a meaningful message including the co-authorship footer
6. `git push -u origin <branch-name>`
7. `gh pr create ...`
8. `gh pr checks <PR-NUMBER> --watch` — wait for all checks
9. Read SonarQube results; fix any code smells, hotspots, bugs, or coverage gaps
10. Commit fixes and push; repeat until all checks are green or 10-commit limit reached

**Example 2: User says "commit this refactoring"**

Actions:
1. Confirm current branch — create one if on `main`
2. Stage only the refactored files
3. Commit: `refactor(detector): simplify two-phase categorization logic`
4. Push and offer to open a PR

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

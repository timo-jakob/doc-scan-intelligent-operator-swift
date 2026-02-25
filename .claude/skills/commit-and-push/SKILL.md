---
name: commit-and-push
description: End-of-task skill that formats, lints, commits, and pushes changes on the current feature branch. Use when a task is finished locally and looks good — "commit this", "commit and push", "ship it", "done, commit", or similar. Enforces branch-based workflow — REFUSES to run on main. Runs SwiftFormat → SwiftLint → stage → commit → push so the work is reviewable on the remote immediately.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 3.0.0
  category: workflow
---

# Commit and Push

Use this skill to wrap up a completed task: format, lint, commit, and push — all in one go. The goal is to make the work reviewable on the remote as quickly as possible.

## Rules — always follow these

1. **REFUSE to run on `main`** — if the current branch is `main`, **stop immediately** and tell the user to create a feature branch first. Do NOT create a branch on their behalf. Do NOT proceed with any further steps. This is a hard block.
2. **Use `git switch`** to change branches — never `git checkout`
3. **Format before lint, lint before staging** — always in this exact order: `make format` → `make lint` → stage → commit → push
4. **Fix ALL lint violations before staging** — both errors and warnings (`line_length`, `type_body_length`, `function_body_length`, `file_length`, etc.) must be resolved to achieve zero violations
5. **Never use `git add -A` or `git add .`** — always stage specific files by name to avoid accidentally including build artifacts or credentials
6. **Always include the co-authorship footer** in every commit message
7. **Do NOT ask for approval** — generate the commit message, commit, and push directly
8. **Always push after a successful commit** — the branch must be up to date on the remote so the work is reviewable

---

## Instructions

### Step 1: Guard — refuse if on `main`

```bash
git branch --show-current
```

If the output is `main`:
- **STOP. Do not continue.**
- Tell the user: "You are on `main`. Please create a feature branch first (`git switch -c <branch-name>`) and try again."
- Do NOT create the branch yourself. Do NOT proceed to formatting or linting.

If on any other branch, proceed.

### Step 2: Format

```bash
make format
```

### Step 3: Lint

```bash
make lint
```

If `make lint` reports **any violations** (errors or warnings), fix them all before continuing. The goal is **0 violations, 0 serious**.

Common fixes for warnings:
- `file_length` → split the file (e.g. extract an extension into `Foo+Bar.swift`)
- `type_body_length` → move methods into extensions in separate files
- `function_body_length` → extract helper methods
- `line_length` → break long lines

> SwiftFormat rewrites files in-place, which can occasionally shift line numbers and surface new SwiftLint violations on reformatted lines. After fixing any violations, run `make lint` a second time to confirm a clean state before staging.

### Step 4: Inspect the diff and generate a commit message

```bash
git diff
git status
```

> Do not run `git diff --staged` here — nothing is staged yet, so it will always be empty. Inspect the unstaged diff (`git diff`) instead, which contains all pending changes.

Analyze all changed files. Generate a commit message following the Conventional Commits format:

```
<type>(<optional scope>): <short summary in present tense, lowercase>

<optional body — explain WHY, not what the code does>

Co-Authored-By: Claude Code <noreply@anthropic.com>
```

**Type** reflects the nature of the change:
- `feat` — new feature or capability
- `fix` — bug fix
- `refactor` — restructuring without behaviour change
- `test` — tests added or updated
- `docs` — documentation only
- `chore` — build, tooling, CI, dependencies
- `perf` — performance improvement

**Scope** is the module or component affected (e.g. `cli`, `ocr`, `pdf`, `detector`, `deps`).

Good examples:
- `fix(cli): hide download progress bar when model is already cached`
- `feat(ocr): add keyword detection for prescription documents`
- `refactor(detector): extract categorization into separate method`
- `chore(deps): update mlx-swift-lm to 2.30.0`
- `test(string-utils): add edge cases for doctor name sanitization`

Bad examples (never use): `fix stuff`, `WIP`, `changes`, `update`, `misc`

**Do NOT ask the user for approval. Proceed directly to staging, committing, and pushing.**

### Step 5: Stage specific files

Stage only the files that contain the relevant changes:

```bash
git add <file1> <file2> ...
git status  # verify exactly what is staged
```

Never use `git add -A` or `git add .`.

### Step 6: Commit

Use a HEREDOC to pass the message, preserving formatting exactly:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<optional body>

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

### Step 7: Push

Push the branch to the remote. Use `-u` on the first push to set up tracking:

```bash
# First push (no upstream yet)
git push -u origin $(git branch --show-current)

# Subsequent pushes (upstream already set)
git push
```

To determine which to use, check if the branch has an upstream:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no-upstream"
```

If `no-upstream`, use `git push -u origin <branch>`. Otherwise, use `git push`.

### Step 8: Confirm and report

```bash
git status
git log --oneline -1
```

Report to the user:
- The commit hash and message
- That the branch has been pushed
- The remote branch name (for easy PR creation)

---

## Examples

**Example 1: User says "commit and push" on a feature branch**

1. `git branch --show-current` → `fix/resolve-date-extraction` (not `main`, proceed)
2. `make format`
3. `make lint` — fix all violations (errors and warnings)
4. `git diff` — inspect all changes
5. `git add Sources/DocScanCLI/DocScanCommand.swift`
6. `git status` — verify staged files
7. Commit directly:
   ```bash
   git commit -m "$(cat <<'EOF'
   fix(cli): hide progress bar for cached models

   Hide progress bar when models are loaded from cache to avoid flicker.

   Co-Authored-By: Claude Code <noreply@anthropic.com>
   EOF
   )"
   ```
8. `git push -u origin fix/resolve-date-extraction`
9. Report: committed `abc1234`, pushed to `origin/fix/resolve-date-extraction`

**Example 2: User says "ship it" while on `main`**

1. `git branch --show-current` → `main`
2. **STOP.** Tell the user: "You are on `main`. Please create a feature branch first and try again."
3. Do NOT proceed further.

**Example 3: Branch already has upstream tracking**

1. `git branch --show-current` → `feature/add-ocr-keywords` (not `main`, proceed)
2. Format → lint → stage → commit (steps 2–7 as above)
3. `git rev-parse --abbrev-ref --symbolic-full-name @{u}` → `origin/feature/add-ocr-keywords`
4. `git push` (upstream already set, no `-u` needed)
5. Report success

---

## Troubleshooting

**`make lint` reports violations in files I didn't change**

Fix violations in files you modified. If a warning appears in an unrelated file, fix it too — the goal is always 0 violations project-wide.

**Push rejected (remote has new commits)**

```bash
git pull --rebase origin $(git branch --show-current)
# Resolve conflicts if any, then push again
git push
```

**Merge conflict after rebase**

```bash
git pull --rebase origin main
# Resolve conflicts, then continue
git rebase --continue
git push
```

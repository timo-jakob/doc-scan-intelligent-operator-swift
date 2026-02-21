---
name: prepare-commit
description: Prepares and creates a git commit for this project. Use when the user says "commit this", "commit these changes", "let's commit", "stage and commit", or similar. Enforces branch-based workflow — never commits directly to main. Always runs SwiftFormat then SwiftLint in sequence before staging. Auto-proposes a Conventional Commit message based on the diff for user approval.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 1.0.0
  category: workflow
---

# Prepare Commit

## Rules — always follow these

1. **Never commit directly to `main`** — all changes go through a feature branch
2. **Use `git switch`** to change branches — never `git checkout`
3. **Format before lint, lint before staging** — always in this exact order: `make format` → `make lint` → stage → commit
4. **Fix lint errors before staging** — warnings in `Sources/` (`line_length`, `large_tuple`, `function_body_length`, etc.) are pre-existing and acceptable; do not introduce new ones
5. **Never use `git add -A` or `git add .`** — always stage specific files by name to avoid accidentally including build artifacts or credentials
6. **Always include the co-authorship footer** in every commit message

---

## Instructions

### Step 1: Check the current branch

```bash
git status
git branch --show-current
```

If on `main`, determine the appropriate branch name from context (what was changed and why), then create it:

```bash
git switch -c <type>/<short-description-in-kebab-case>
```

| Prefix | Use for |
|---|---|
| `feature/` | New functionality or capabilities |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring without behaviour change |
| `test/` | Adding or updating tests |
| `docs/` | Documentation only |
| `chore/` | Build system, dependencies, tooling, CI |
| `perf/` | Performance improvements |

If already on a feature branch, proceed without switching.

### Step 2: Format

```bash
make format
```

### Step 3: Lint

```bash
make lint
```

If `make lint` reports any **errors** (not warnings), fix them before continuing. Do not introduce new warnings.

### Step 4: Inspect the diff and propose a commit message

```bash
git diff
git diff --staged
git status
```

Analyze all changed files. Draft a commit message following the Conventional Commits format:

```
<type>(<optional scope>): <short summary in present tense, lowercase>

<optional body — explain WHY, not what the code does>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
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

**Show the proposed message to the user and ask for approval or edits before committing.**

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

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Confirm success:

```bash
git status
```

---

## Examples

**Example 1: User says "commit this"**

1. `git branch --show-current` — confirm not on `main`
2. `make format`
3. `make lint` — fix any errors
4. `git diff` — inspect all changes
5. Propose: `fix(cli): hide progress bar for cached models` — show to user, wait for approval
6. `git add Sources/DocScanCLI/DocScanCommand.swift`
7. `git status` — verify staged files
8. Commit using the HEREDOC form from Step 6 to preserve body and co-authorship footer:
   ```bash
   git commit -m "$(cat <<'EOF'
   fix(cli): hide progress bar for cached models

   Hide progress bar when models are loaded from cache to avoid flicker.

   Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
   EOF
   )"
   ```
9. Report success

**Example 2: User says "commit these changes" while on `main`**

1. Determine branch name from context: `fix/resolve-date-extraction`
2. `git switch -c fix/resolve-date-extraction`
3. `make format` → `make lint` → fix any errors
4. `git diff` — inspect changes, draft commit message
5. Show proposed message to user, get approval
6. Stage specific files → commit

---

## Troubleshooting

**Accidentally on `main` before committing**

```bash
git switch -c <correct-branch-name>
# Staged and unstaged changes move with you automatically
```

**Accidentally committed to `main`**

```bash
git switch -c <correct-branch-name>
git switch main
git reset --hard origin/main
```

**`make lint` reports errors in files I didn't change**

Fix only errors in files you modified. Do not refactor surrounding code that was not part of the change.

**Merge conflict after branch creation**

```bash
git pull --rebase origin main
# Resolve conflicts, then continue
```

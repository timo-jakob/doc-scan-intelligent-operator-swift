---
name: git-github
description: Handles all git and GitHub workflow actions for this project. Use when the user says "push this to GitHub", "create a PR", "commit this", "let's push", "open a pull request", "create a branch", or "we can push this". Enforces branch-based workflow — never commits directly to main.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 1.0.0
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

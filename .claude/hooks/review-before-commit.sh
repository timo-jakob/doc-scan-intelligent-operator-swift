#!/bin/bash
# .claude/hooks/review-before-commit.sh
#
# Pre-commit quality gate: triggers the swift-code-reviewer subagent
# when Claude Code is about to commit Swift files.
#
# Hook context is passed as JSON via stdin by Claude Code.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Only trigger when the Bash tool is running a git commit
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  # Check if any staged files are Swift files
  STAGED_SWIFT=$(git diff --cached --name-only -- '*.swift' 2>/dev/null)

  if [[ -n "$STAGED_SWIFT" ]]; then
    FILE_COUNT=$(echo "$STAGED_SWIFT" | wc -l | tr -d ' ')
    echo "⏸️  PRE-COMMIT REVIEW: ${FILE_COUNT} staged Swift file(s) detected."
    echo "Before committing, use the swift-code-reviewer subagent to review all staged Swift changes."
    echo "Only proceed with the commit after all 🔴 Critical issues are resolved."
    echo ""
    echo "Staged Swift files:"
    echo "$STAGED_SWIFT" | sed 's/^/  - /'
  fi
fi
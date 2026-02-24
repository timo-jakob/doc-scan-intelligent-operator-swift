---
description: Run the Swift code reviewer on all recent changes
argument-hint: "[optional: specific file or directory to review]"
---

## Swift Code Review

Use the **swift-code-reviewer** subagent to perform a comprehensive review of all Swift files that
have been modified since the last commit.

If an argument is provided, scope the review to that file or directory only.

### Review scope

1. Determine which Swift files to review:
   - If a specific path was provided as argument, review only that path
   - Otherwise, review all modified Swift files: `git diff --name-only -- '*.swift'` and
     `git diff --staged --name-only -- '*.swift'`
   - If no git changes are found, review all Swift files in `Sources/`

2. Delegate the full review to the **swift-code-reviewer** subagent.

3. After the review completes, summarize the findings and:
   - **Automatically fix** all 🔴 Critical issues
   - **Automatically fix** all 🟡 Warning issues
   - **Automatically fix** all auto-fixable linting/formatting issues (`swiftlint --fix`, `swift-format format`)
   - **List** remaining 🟢 Suggestions for the developer to decide on
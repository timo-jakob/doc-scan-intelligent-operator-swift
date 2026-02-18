---
name: mlx-build-debug
description: Guides building and debugging this MLX Swift project. Use when building the binary, when seeing "Failed to load the default metallib", when MLX model inference crashes at startup, or when setting up the development environment. Always use xcodebuild — never swift build.
metadata:
  author: doc-scan-intelligent-operator-swift
  version: 1.1.0
  category: developer-tooling
---

# MLX Build & Debug

## Instructions

### Step 1: Build with xcodebuild — always

This is the only build method for this project. MLX requires Metal shaders compiled and bundled at build time. `swift build` skips this step and produces a binary that crashes when any MLX model is loaded.

```bash
xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build
```

Expected output: `** BUILD SUCCEEDED **`

### Step 2: Locate the binary

```bash
ls ~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan
```

### Step 3: Run and verify

```bash
~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan <file.pdf> --dry-run -v
```

If Metal loaded correctly, model inference starts (downloading or loading from cache). If it crashes immediately on the first model call, go back to Step 1.

## Examples

**Example 1: Developer asks how to build**

User says: "How do I build and run this project?"

Actions:
1. Provide the `xcodebuild` command from Step 1
2. Show how to find the binary in DerivedData (Step 2)
3. Provide a sample run command (Step 3)

Result: Working binary with full MLX inference support

**Example 2: Binary crashes on model load**

User says: "My build works but crashes when loading the model"

Actions:
1. Ask how they built — if they used `swift build`, that is the cause
2. Run the `xcodebuild` command from Step 1
3. Use the DerivedData binary, not `.build/debug/docscan`

Result: Inference starts successfully

## Troubleshooting

**Error: `MLX error: Failed to load the default metallib. library not found`**
Cause: Binary was built with `swift build`
Solution: Rebuild with `xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build`

**Error: `library not found for -lMLX` (linker error)**
Cause: Xcode Command Line Tools missing or outdated
Solution: `xcode-select --install`

**Error: Model download stalls or fails**
Cause: Network issue or `~/.cache/docscan/models/` not writable
Solution: Check directory permissions; delete partial download folder and retry

**Error: `malloc: Region cookie corrupted` or memory crash**
Cause: RAM pressure — model too large for available unified memory
Solution: Use a smaller quantized model variant (e.g. 2B instead of 7B)

**Symptom: Very slow first run**
Cause: Model downloading from Hugging Face on first use
Solution: Normal — model is cached at `~/.cache/docscan/models/` after first run

## Clean build

```bash
# Clean SPM artifacts
swift package clean

# Clean Xcode DerivedData for this project
rm -rf ~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*

# Rebuild
xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build
```

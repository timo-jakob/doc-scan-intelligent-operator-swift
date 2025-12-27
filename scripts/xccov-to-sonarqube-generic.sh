#!/usr/bin/env bash
# Converts Xcode code coverage to SonarQube generic coverage format
# Based on: https://github.com/SonarSource/sonar-scanning-examples/tree/master/swift-coverage
# Modified to:
# 1. Output relative paths for proper SonarQube matching
# 2. Filter to only include project source files (not dependencies)

set -euo pipefail

# Get the repository root for converting absolute paths to relative
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

function convert_file_coverage {
  local file_path="$1"
  local xcresult="$2"

  # Get relative path
  local relative_path="${file_path#$REPO_ROOT/}"

  # Only process files in Sources/ directory
  if [[ "$relative_path" != Sources/* ]]; then
    return
  fi

  echo "  <file path=\"$relative_path\">"

  # Get line coverage for this file
  xcrun xccov view --archive --file "$file_path" "$xcresult" 2>/dev/null | \
    sed -n \
      -e 's/^ *\([0-9][0-9]*\): 0.*$/    <lineToCover lineNumber="\1" covered="false"\/>/p' \
      -e 's/^ *\([0-9][0-9]*\): [1-9].*$/    <lineToCover lineNumber="\1" covered="true"\/>/p'

  echo "  </file>"
}

function xccov_to_generic {
  local xcresult="$1"

  echo '<coverage version="1">'

  # Get list of all files with coverage data
  xcrun xccov view --archive --file-list "$xcresult" 2>/dev/null | while read -r file_path; do
    # Only process files that are in our repository
    if [[ "$file_path" == "$REPO_ROOT"/* ]]; then
      convert_file_coverage "$file_path" "$xcresult"
    fi
  done

  echo '</coverage>'
}

function check_xcode_version() {
  local major=${1:-0} minor=${2:-0}
  return $(( (major >= 14) || (major == 13 && minor >= 3) ))
}

# Validate Xcode version
if ! xcode_version="$(xcodebuild -version | sed -n '1s/^Xcode \([0-9.]*\)$/\1/p')"; then
  echo 'Failed to get Xcode version' 1>&2
  exit 1
elif check_xcode_version ${xcode_version//./ }; then
  echo "Xcode version '$xcode_version' not supported, version 13.3 or above is required" 1>&2
  exit 1
fi

# Validate input
xcresult="$1"
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path/to/*.xcresult>"
  echo "Invalid number of arguments. Expecting 1 path matching '*.xcresult'"
  exit 1
elif [[ ! -d $xcresult ]]; then
  echo "Path not found: $xcresult" 1>&2
  exit 1
elif [[ $xcresult != *".xcresult"* ]]; then
  echo "Expecting input to match '*.xcresult', got: $xcresult" 1>&2
  exit 1
fi

xccov_to_generic "$xcresult"

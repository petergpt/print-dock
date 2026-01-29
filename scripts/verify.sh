#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "==> swift build"
swift build

SDK_PATH=""
if command -v xcrun >/dev/null 2>&1; then
  SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
fi

if [ -n "$SDK_PATH" ] && [ -d "$SDK_PATH/System/Library/Frameworks/XCTest.framework" ]; then
  echo "==> swift test"
  swift test
else
  echo "==> swift test (skipped: XCTest not available)"
fi

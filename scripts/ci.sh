#!/bin/sh
set -eu

PROJECT="HHCServerManager.xcodeproj"
SCHEME="HHCServerManager"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"

cd "$(dirname "$0")/.."

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  test

#!/bin/bash
set -euo pipefail

BUNDLE_ID="com.screenslice.app"
APP_BUNDLE=".build/release/ScreenSlice.app"

# Reset screen recording permission (stale after re-codesign)
echo "Resetting screen capture permission for $BUNDLE_ID..."
tccutil reset ScreenCapture "$BUNDLE_ID"

# Build + bundle + codesign
echo "Building..."
"$(dirname "$0")/build-app.sh"

# Launch the app
echo "Launching ScreenSlice..."
open "$APP_BUNDLE"

echo "Done."

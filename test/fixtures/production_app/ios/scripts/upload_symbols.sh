#!/bin/sh
# Uploads dSYMs to Crashlytics for Release builds only.
set -eu
[ "${CONFIGURATION}" = "Release" ] || exit 0
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"

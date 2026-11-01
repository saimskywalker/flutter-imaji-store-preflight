#!/bin/sh
# iOS flavors without Xcode configurations: every flavor builds with the
# stock Debug/Release/Profile configurations, and this script copies the
# flavor's Firebase config and xcconfig values into place.
#
#   flutter build ipa --dart-define=FLAVOR=prod
set -eu

flavor=dev
for define in $(echo "${DART_DEFINES:-}" | tr ',' ' '); do
  decoded=$(echo "$define" | base64 --decode)
  case "$decoded" in
    FLAVOR=*) flavor="${decoded#FLAVOR=}" ;;
  esac
done

config="$SRCROOT/config/$flavor"
if [ ! -d "$config" ]; then
  echo "error: unknown flavor '$flavor' (expected dev or prod)" >&2
  exit 1
fi

mkdir -p "$SRCROOT/config/current"
cp "$config/Flavor.xcconfig" "$SRCROOT/config/current/Flavor.xcconfig"
cp "$config/GoogleService-Info.plist" \
  "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"

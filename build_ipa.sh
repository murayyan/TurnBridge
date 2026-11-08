#!/bin/bash
# Build an unsigned TurnBridge.ipa without Xcode, using a standalone iPhoneOS SDK.
#
#   ./build_ipa.sh                       # uses $SDK or /tmp/sdk_test/iPhoneOS18.6.sdk
#   SDK=/path/to/iPhoneOS18.6.sdk ./build_ipa.sh
#
# The result is unsigned on purpose: Sideloadly / AltStore re-signs it with your
# Apple ID at install time.
set -euo pipefail

cd "$(dirname "$0")"

SDK="${SDK:-/tmp/sdk_test/iPhoneOS18.6.sdk}"
TARGET="${TARGET:-arm64-apple-ios16.0}"
OUT="dist"
APP="$OUT/Payload/TurnBridge.app"

if [ ! -d "$SDK" ]; then
  echo "iOS SDK not found at $SDK" >&2
  echo "Fetch one, e.g.:" >&2
  echo "  git clone --depth 1 --filter=blob:none --sparse https://github.com/xybp888/iOS-SDKs /tmp/sdk_test" >&2
  echo "  cd /tmp/sdk_test && git sparse-checkout set iPhoneOS18.6.sdk" >&2
  exit 1
fi

echo "==> compiling"
mkdir -p "$OUT"
SDKROOT="$SDK" swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -O \
  -o "$OUT/TurnBridge" \
  Sources/*.swift

echo "==> bundling"
rm -rf "$OUT/Payload"
mkdir -p "$APP"
cp "$OUT/TurnBridge" "$APP/TurnBridge"
cp Info.plist "$APP/Info.plist"
cp Icons/*.png "$APP/" 2>/dev/null || true
printf 'APPL????' > "$APP/PkgInfo"
chmod +x "$APP/TurnBridge"

echo "==> zipping"
rm -f "$OUT/TurnBridge.ipa"
(cd "$OUT" && zip -qr TurnBridge.ipa Payload)
rm -f "$OUT/TurnBridge"

ls -lh "$OUT/TurnBridge.ipa"
echo "done: $OUT/TurnBridge.ipa (unsigned)"

#!/bin/sh
# Build, launch with demo data on a tab, and screenshot: tools/shot.sh plan out.png [extra args]
set -e
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
TAB=$1; OUT=$2; shift 2
UDID=${UDID:-2162CFF6-A08E-480E-9A7B-71A62914182E}
xcodegen generate >/dev/null
xcodebuild -project Bench.xcodeproj -scheme BenchTest -destination "id=$UDID" -derivedDataPath "${TMPDIR:-/tmp}/bench2-dd" build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD FAILED" && exit 1
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "${TMPDIR:-/tmp}/bench2-dd/Build/Products/Debug-iphonesimulator/BenchTest.app"
xcrun simctl terminate "$UDID" me.fybre.dosebook.test 2>/dev/null || true
xcrun simctl launch "$UDID" me.fybre.dosebook.test -demo -tab "$TAB" "$@" >/dev/null
sleep "${WAIT:-3}"
xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null
echo "$OUT"

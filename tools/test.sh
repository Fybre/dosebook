#!/bin/sh
# Runs the BenchCore suite in several time zones. The original runs its tests in
# America/New_York; DST bugs only show in some zones, so check more than one.
set -e
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/../BenchCore"
for tz in America/New_York Europe/London Asia/Kolkata Australia/Sydney; do
  echo "== TZ=$tz"
  TZ=$tz swift test --scratch-path "${TMPDIR:-/tmp}/bench2-build" "$@" 2>&1 | grep -E "recorded an issue|Test run with" | tail -40
done

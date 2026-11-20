#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_app="$PWD/build/Notchbox-Tests.app"
Scripts/build-app.sh "${1:-debug}" "$test_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.littleguys.notchbox.tests' "$test_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Notchbox Tests' "$test_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Notchbox Tests' "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
fixture_app="$PWD/build/Notchbox-Focus-Fixture.app"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc Scripts/FocusFixture.swift -o "$fixture_app/Contents/MacOS/FocusFixture"
cp Resources/Info.plist "$fixture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.littleguys.notchbox.focus-fixture' "$fixture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable FocusFixture' "$fixture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Notchbox Focus Fixture' "$fixture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Notchbox Focus Fixture' "$fixture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$fixture_app/Contents/Info.plist"
codesign --force --deep --sign - "$fixture_app"
NOTCHBOX_FOCUS_FIXTURE_APP="$fixture_app" \
NOTCHBOX_SMOKE_REPORT="${NOTCHBOX_SMOKE_REPORT:-$PWD/build/smoke-results.json}" \
  "$test_app/Contents/MacOS/Notchbox" --smoke-test

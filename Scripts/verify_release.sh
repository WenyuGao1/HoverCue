#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
derived_data=${1:-"${project_root}/DerivedData/ReleaseVerification"}
derived_data=${derived_data:A}
app_path="${derived_data}/Build/Products/Release/HoverCue.app"
entitlements_dump=$(mktemp -t hovercue-entitlements.XXXXXX)

cleanup() {
    rm -f "${entitlements_dump}"
}
trap cleanup EXIT

cd "${project_root}"

for strings_file in Config/Info.plist LocalDualCaption/*.lproj/InfoPlist.strings LocalDualCaption/*.lproj/Localizable.strings; do
    plutil -lint "${strings_file}" >/dev/null
done

xcodebuild \
    -quiet \
    -project LocalDualCaption.xcodeproj \
    -scheme LocalDualCaption \
    -configuration Debug \
    -derivedDataPath "${derived_data}" \
    -destination 'platform=macOS,arch=arm64' \
    test

xcodebuild \
    -quiet \
    -project LocalDualCaption.xcodeproj \
    -scheme LocalDualCaption \
    -configuration Release \
    -derivedDataPath "${derived_data}" \
    -destination 'platform=macOS,arch=arm64' \
    analyze

xcodebuild \
    -quiet \
    -project LocalDualCaption.xcodeproj \
    -scheme LocalDualCaption \
    -configuration Release \
    -derivedDataPath "${derived_data}" \
    -destination 'platform=macOS,arch=arm64' \
    build

test -d "${app_path}"
codesign --verify --deep --strict "${app_path}"
codesign -d --entitlements :- "${app_path}" >"${entitlements_dump}" 2>/dev/null

plutil -extract 'com\.apple\.security\.app-sandbox' raw "${entitlements_dump}" | grep -qx true
plutil -extract 'com\.apple\.security\.device\.audio-input' raw "${entitlements_dump}" | grep -qx true
plutil -extract 'com\.apple\.security\.personal-information\.speech-recognition' raw "${entitlements_dump}" | grep -qx true

plutil -extract 'com\.apple\.security\.files\.user-selected\.read-write' raw "${entitlements_dump}" | grep -qx true

for forbidden_key in \
    'com\.apple\.security\.network\.client' \
    'com\.apple\.security\.device\.camera' \
    'com\.apple\.security\.get-task-allow'; do
    if plutil -extract "${forbidden_key}" raw "${entitlements_dump}" >/dev/null 2>&1; then
        print -u2 "Forbidden entitlement present: ${forbidden_key}"
        exit 1
    fi
done

test "$(defaults read "${app_path}/Contents/Info" CFBundleDisplayName)" = "HoverCue"
test "$(defaults read "${app_path}/Contents/Info" CFBundleIdentifier)" = "com.wenyugao.hovercue"
test "$(defaults read "${app_path}/Contents/Info" CFBundleShortVersionString)" = "1.0.2"
test "$(defaults read "${app_path}/Contents/Info" CFBundleVersion)" = "30"
test ! -e "${app_path}/Contents/Frameworks"

print "HoverCue release verification passed: ${app_path}"

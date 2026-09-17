#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppBundle/Info.plist)}"
app="dist/MouseTalk.app"
binary="$app/Contents/MacOS/DoubleClickMouse"
app_archive="dist/MouseTalk-$version-universal.zip"
source_archive="dist/MouseTalk-$version-source.tar.gz"
checksums="dist/SHA256SUMS.txt"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "$app" ]] || fail "missing $app"
[[ -f "$binary" ]] || fail "missing app executable"
[[ -f "$app_archive" ]] || fail "missing $app_archive"
[[ -f "$source_archive" ]] || fail "missing $source_archive"
[[ -f "$checksums" ]] || fail "missing $checksums"

plutil -lint "$app/Contents/Info.plist" >/dev/null
actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$actual_version" == "$version" ]] || fail "app version $actual_version does not match $version"
display_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Contents/Info.plist")
[[ "$display_name" == "妙语 MouseTalk" ]] || fail "unexpected display name: $display_name"

codesign --verify --deep --strict "$app"
lipo "$binary" -verify_arch arm64 x86_64
unzip -t "$app_archive" >/dev/null
tar -tzf "$source_archive" >/dev/null
(cd dist && shasum -a 256 -c SHA256SUMS.txt)

if spctl --assess --type execute "$app" >/dev/null 2>&1; then
  gatekeeper="accepted"
else
  gatekeeper="rejected (expected until Developer ID signing and notarization are complete)"
  if [[ "${REQUIRE_GATEKEEPER:-0}" == "1" ]]; then
    fail "Gatekeeper rejected the app"
  fi
fi

echo "Release candidate verified: MouseTalk $version"
echo "Architectures: $(lipo -archs "$binary")"
echo "Gatekeeper: $gatekeeper"
echo "Artifacts: $app_archive, $source_archive, $checksums"

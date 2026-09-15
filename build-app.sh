#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_name="MouseTalk.app"
output_root="$project_dir/dist"
output_path="$output_root/$app_name"
staging_root="$(mktemp -d)"
staging_app="$staging_root/$app_name"

cleanup() {
  /bin/rm -rf "$staging_root"
}
trap cleanup EXIT

cd "$project_dir"
build_arch_args=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  build_arch_args=(--arch arm64 --arch x86_64)
fi
swift build -c release "${build_arch_args[@]}" --product DoubleClickMouse
app_bin_dir="$(swift build -c release "${build_arch_args[@]}" --show-bin-path)"
swift build -c release --product mousetalk-check

mkdir -p "$staging_app/Contents/MacOS"
cp "$app_bin_dir/DoubleClickMouse" "$staging_app/Contents/MacOS/DoubleClickMouse"
cp "$project_dir/AppBundle/Info.plist" "$staging_app/Contents/Info.plist"
mkdir -p "$staging_app/Contents/Resources"
"$project_dir/.build/release/mousetalk-check" --export-assets "$staging_root/brand"
iconutil -c icns "$staging_root/brand/MouseTalk.iconset" -o "$staging_app/Contents/Resources/MouseTalk.icns"
chmod 755 "$staging_app/Contents/MacOS/DoubleClickMouse"

# A developer can pin a local identity once; it is never committed or
# auto-selected from the keychain. An explicit environment value wins.
signing_identity="${SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" && -f "$project_dir/.signing-identity" ]]; then
  signing_identity="$(<"$project_dir/.signing-identity")"
fi
if [[ -n "$signing_identity" ]]; then
  codesign --force --deep --options runtime --sign "$signing_identity" "$staging_app"
  echo "Signed with the configured identity (SIGNING_IDENTITY or .signing-identity)."
else
  codesign --force --deep --sign - "$staging_app"
  echo "Used ad-hoc signing. Rebuilds may require permissions again."
fi

mkdir -p "$output_root"
/bin/rm -rf "$output_path"
mv "$staging_app" "$output_path"

echo "Built: $output_path"
echo "Open it with: open '$output_path'"

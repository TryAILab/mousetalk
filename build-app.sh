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
swift build -c release --product DoubleClickMouse
swift build -c release --product mousetalk-check

mkdir -p "$staging_app/Contents/MacOS"
cp "$project_dir/.build/release/DoubleClickMouse" "$staging_app/Contents/MacOS/DoubleClickMouse"
cp "$project_dir/AppBundle/Info.plist" "$staging_app/Contents/Info.plist"
mkdir -p "$staging_app/Contents/Resources"
"$project_dir/.build/release/mousetalk-check" --export-assets "$staging_root/brand"
iconutil -c icns "$staging_root/brand/MouseTalk.iconset" -o "$staging_app/Contents/Resources/MouseTalk.icns"
chmod 755 "$staging_app/Contents/MacOS/DoubleClickMouse"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$staging_app"
  echo "Signed with the identity supplied through SIGNING_IDENTITY."
else
  codesign --force --deep --sign - "$staging_app"
  echo "Used ad-hoc signing. Rebuilds may require permissions again."
fi

mkdir -p "$output_root"
/bin/rm -rf "$output_path"
mv "$staging_app" "$output_path"

echo "Built: $output_path"
echo "Open it with: open '$output_path'"

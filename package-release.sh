#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# Distribution package is explicitly ad-hoc unless a Developer ID is supplied.
UNIVERSAL=1 SIGNING_IDENTITY="${RELEASE_SIGNING_IDENTITY:--}" ./build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/MouseTalk.app/Contents/Info.plist)
archive="MouseTalk-$version-universal.zip"
codesign --verify --deep --strict dist/MouseTalk.app
lipo dist/MouseTalk.app/Contents/MacOS/DoubleClickMouse -verify_arch arm64 x86_64
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent dist/MouseTalk.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "Release archive: dist/$archive"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Refusing to package a dirty worktree. Commit or stash project changes first." >&2
  exit 1
fi

# Distribution package is explicitly ad-hoc unless a Developer ID is supplied.
UNIVERSAL=1 SIGNING_IDENTITY="${RELEASE_SIGNING_IDENTITY:--}" ./build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/MouseTalk.app/Contents/Info.plist)
archive="MouseTalk-$version-universal.zip"
source_archive="MouseTalk-$version-source.tar.gz"
codesign --verify --deep --strict dist/MouseTalk.app
lipo dist/MouseTalk.app/Contents/MacOS/DoubleClickMouse -verify_arch arm64 x86_64
rm -f "dist/$archive" "dist/$source_archive"
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent dist/MouseTalk.app "dist/$archive"
git archive --format=tar.gz --prefix="mousetalk-$version/" -o "dist/$source_archive" HEAD
(cd dist && shasum -a 256 "$archive" "$source_archive" > SHA256SUMS.txt)
./scripts/verify-release.sh "$version"
echo "Release archive: dist/$archive"
echo "Source archive: dist/$source_archive"

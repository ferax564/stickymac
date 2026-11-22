#!/bin/bash
# Builds, signs, notarizes and publishes StickyMac to GitHub Releases.
# Needs a Developer ID Application identity in Keychain and a notarytool Keychain profile.
# Usage: scripts/release.sh   (publishes the version set in build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

identity=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/"Developer ID Application: / { print $2; exit }')}
[[ -n "$identity" ]] || { echo "No Developer ID Application identity in Keychain. Set SIGN_IDENTITY." >&2; exit 1; }
profile=${NOTARY_PROFILE:-QFind}
version=$(sed -n 's:.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*:\1:p' build.sh)
tag="v$version"
[[ -z $(git status --porcelain) ]] || { echo "Commit your changes before releasing." >&2; exit 1; }
git fetch -q origin
[[ $(git rev-parse HEAD) == $(git rev-parse '@{u}') ]] || { echo "Push HEAD before releasing." >&2; exit 1; }
! gh release view "$tag" >/dev/null 2>&1 || { echo "Release $tag already exists. Bump the version in build.sh." >&2; exit 1; }

SIGN_IDENTITY="$identity" ./build.sh
app=build/StickyMac.app
stage=$(mktemp -d build/.release.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto -c -k --keepParent "$app" "$stage/submission.zip"
xcrun notarytool submit "$stage/submission.zip" --keychain-profile "$profile" --wait --output-format json > "$stage/result.json"
[[ $(plutil -extract status raw "$stage/result.json") == Accepted ]] || { cat "$stage/result.json" >&2; exit 1; }
xcrun stapler staple "$app"
codesign --verify --strict --deep "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir "$stage/out"
ditto -c -k --keepParent "$app" "$stage/out/StickyMac.zip"
(cd "$stage/out" && shasum -a 256 StickyMac.zip > StickyMac.zip.sha256)
gh release create "$tag" "$stage/out/StickyMac.zip" "$stage/out/StickyMac.zip.sha256" \
  --target "$(git rev-parse HEAD)" --title "StickyMac $tag" --notes-file .github/release-notes.md
echo "Published $tag"

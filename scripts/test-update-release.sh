#!/bin/sh
# Tests scripts/update-release.sh in a temporary git repo with copies of Package.swift, README.md and the script.
# The real checkout does not change. Usage: scripts/test-update-release.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A fixed identity, so that the test also commits on a CI runner with no git identity.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
repo=$tmp/repo
mkdir -p "$repo/scripts"
cp "$root/Package.swift" "$root/README.md" "$repo/"
cp "$root/scripts/update-release.sh" "$repo/scripts/"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" commit -q -m base

# A fake zip outside the repo. The script only hashes it.
mkdir -p "$tmp/zip/CodelloySDK.xcframework"
echo fake >"$tmp/zip/CodelloySDK.xcframework/Info.plist"
(cd "$tmp/zip" && zip -qr ../CodelloySDK-9.9.9.xcframework.zip CodelloySDK.xcframework)
zip=$tmp/CodelloySDK-9.9.9.xcframework.zip
sum=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)

"$repo/scripts/update-release.sh" 9.9.9 "$zip" >"$tmp/out" || fail "a valid release failed: $(cat "$tmp/out")"
grep -qx 'let version = "9.9.9"' "$repo/Package.swift" || fail "Package.swift has no version 9.9.9"
grep -qx "let checksum = \"$sum\"" "$repo/Package.swift" || fail "Package.swift has no SHA-256 of the zip"
grep -q 'codelloy-ios", from: "9.9.9")' "$repo/README.md" || fail "README.md has no version 9.9.9"
[ "$(git -C "$repo" rev-list --count HEAD)" = 2 ] || fail "not exactly one new commit"
[ "$(git -C "$repo" diff --name-only HEAD~1 HEAD | tr '\n' ' ')" = "Package.swift README.md " ] ||
    fail "the commit changes other files than Package.swift and README.md"
[ "$(git -C "$repo" log -1 --format=%B)" = "chore(release): CodelloySDK 9.9.9" ] || fail "wrong commit message or a trailer"
[ -z "$(git -C "$repo" tag)" ] || fail "the script made a tag"
grep -q "gh release create 9.9.9 " "$tmp/out" || fail "no gh release command in the output"

# Each bad input fails, makes no commit and changes no file.
expect_failure() {
    commits=$(git -C "$repo" rev-list --count HEAD)
    status=$(git -C "$repo" status --porcelain)
    if "$repo/scripts/update-release.sh" "$@" >/dev/null 2>&1; then
        fail "no failure for: $*"
    fi
    [ "$(git -C "$repo" rev-list --count HEAD)" = "$commits" ] || fail "a commit after a failure for: $*"
    [ "$(git -C "$repo" status --porcelain)" = "$status" ] || fail "a changed file after a failure for: $*"
}
cp "$zip" "$tmp/CodelloySDK-1.0.xcframework.zip"
expect_failure 1.0 "$tmp/CodelloySDK-1.0.xcframework.zip"
expect_failure 9.9.10 "$zip"
expect_failure 9.9.10 "$tmp/CodelloySDK-9.9.10.xcframework.zip"
cp "$zip" "$tmp/CodelloySDK-9.9.10.xcframework.zip"
zip10=$tmp/CodelloySDK-9.9.10.xcframework.zip
echo dirty >>"$repo/README.md"
expect_failure 9.9.10 "$zip10"
git -C "$repo" checkout -q README.md

# The example still on the local package: CI of the release commit would fail.
mkdir -p "$repo/Example/CodelloyExample.xcodeproj"
echo 'relativePath = LocalSDK;' >"$repo/Example/CodelloyExample.xcodeproj/project.pbxproj"
git -C "$repo" add Example
git -C "$repo" commit -q -m "example on LocalSDK"
expect_failure 9.9.10 "$zip10"
git -C "$repo" rm -q -r Example
git -C "$repo" commit -q -m "example on the root package"

# A manifest that does not build the URL from version: the script restores both files.
sed 's|download/\\(version)/CodelloySDK-\\(version)|download/1.0.0/CodelloySDK-1.0.0|' "$repo/Package.swift" >"$tmp/Package.swift"
cp "$tmp/Package.swift" "$repo/Package.swift"
git -C "$repo" commit -q -am "fixed URL"
grep -q 'download/1.0.0/' "$repo/Package.swift" || fail "the test did not change the URL"
expect_failure 9.9.10 "$zip10"

# A README without the dependency line.
echo "# No dependency line" >"$repo/README.md"
git -C "$repo" commit -q -am "no dependency line"
expect_failure 9.9.10 "$zip10"

echo "update-release.sh: all checks pass"

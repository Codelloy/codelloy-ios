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

# Each bad input fails and makes no commit.
expect_failure() {
    commits=$(git -C "$repo" rev-list --count HEAD)
    if "$repo/scripts/update-release.sh" "$@" >/dev/null 2>&1; then
        fail "no failure for: $*"
    fi
    [ "$(git -C "$repo" rev-list --count HEAD)" = "$commits" ] || fail "a commit after a failure for: $*"
}
cp "$zip" "$tmp/CodelloySDK-1.0.xcframework.zip"
expect_failure 1.0 "$tmp/CodelloySDK-1.0.xcframework.zip"
expect_failure 9.9.10 "$zip"
expect_failure 9.9.10 "$tmp/CodelloySDK-9.9.10.xcframework.zip"
cp "$zip" "$tmp/CodelloySDK-9.9.10.xcframework.zip"
echo dirty >>"$repo/README.md"
expect_failure 9.9.10 "$tmp/CodelloySDK-9.9.10.xcframework.zip"
git -C "$repo" checkout -q README.md
# A README without the dependency line: the script changes no file.
echo "# No dependency line" >"$repo/README.md"
git -C "$repo" commit -q -am "no dependency line"
expect_failure 9.9.10 "$tmp/CodelloySDK-9.9.10.xcframework.zip"
[ -z "$(git -C "$repo" status --porcelain)" ] || fail "a failure left a changed file"

echo "update-release.sh: all checks pass"

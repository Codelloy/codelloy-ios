#!/bin/sh
# Tests scripts/update-release.sh in a temporary git repo with copies of Package.swift, README.md and the script.
# The real checkout does not change. Usage: scripts/test-update-release.sh
set -eu
unset CDPATH
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A fixed identity, so that the test also commits on a CI runner with no git identity. No global or system config, so
# that hooks, signing or templates of the machine do not change the test repo.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
repo=$tmp/repo
mkdir -p "$repo/scripts"
cp "$root/Package.swift" "$root/README.md" "$repo/"
cp "$root/scripts/update-release.sh" "$repo/scripts/"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" commit -q -m base

# A fake zip outside the repo. The script only hashes it.
mkdir -p "$tmp/zip/CodelloySDK.xcframework" "$tmp/dist"
echo fake >"$tmp/zip/CodelloySDK.xcframework/Info.plist"
(cd "$tmp/zip" && zip -qr ../dist/CodelloySDK-9.9.9.xcframework.zip CodelloySDK.xcframework)
zip=$tmp/dist/CodelloySDK-9.9.9.xcframework.zip
sum=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)

# A relative zip path with CDPATH set, which makes cd print the directory or go to another one.
(cd "$tmp" && CDPATH=$tmp "$repo/scripts/update-release.sh" 9.9.9 dist/CodelloySDK-9.9.9.xcframework.zip) >"$tmp/out" ||
    fail "a valid release failed: $(cat "$tmp/out")"
grep -qx 'let version = "9.9.9"' "$repo/Package.swift" || fail "Package.swift has no version 9.9.9"
grep -qx "let checksum = \"$sum\"" "$repo/Package.swift" || fail "Package.swift has no SHA-256 of the zip"
grep -q 'codelloy-ios", from: "9.9.9")' "$repo/README.md" || fail "README.md has no version 9.9.9"
[ "$(git -C "$repo" rev-list --count HEAD)" = 2 ] || fail "not exactly one new commit"
[ "$(git -C "$repo" diff --name-only HEAD~1 HEAD | tr '\n' ' ')" = "Package.swift README.md " ] ||
    fail "the commit changes other files than Package.swift and README.md"
[ "$(git -C "$repo" log -1 --format=%B)" = "chore(release): CodelloySDK 9.9.9" ] || fail "wrong commit message or a trailer"
[ -z "$(git -C "$repo" tag)" ] || fail "the script made a tag"
grep -q "gh release create 9.9.9 " "$tmp/out" || fail "no gh release command in the output"
grep -qF "echo \"$sum  $zip\" | shasum -a 256 -c" "$tmp/out" || fail "no check of the zip before the release command"

# Each bad input fails, makes no commit and changes no file.
expect_failure() {
    commits=$(git -C "$repo" rev-list --count HEAD)
    status=$(git -C "$repo" status --porcelain)
    if "$repo/scripts/update-release.sh" "$@" >/dev/null 2>"$tmp/err"; then
        fail "no failure for: $*"
    fi
    [ "$(git -C "$repo" rev-list --count HEAD)" = "$commits" ] || fail "a commit after a failure for: $*"
    [ "$(git -C "$repo" status --porcelain)" = "$status" ] || fail "a changed file after a failure for: $*"
}
# Each zip has the name of its version, so that only the version check can refuse it. 9.9.9 is released already.
for v in 1.0 9.9.9.9 0.0.0 01.2.3 1.02.3 9.9.9 9.9.8; do
    cp "$zip" "$tmp/CodelloySDK-$v.xcframework.zip"
    expect_failure "$v" "$tmp/CodelloySDK-$v.xcframework.zip"
done
expect_failure 9.9.10 "$zip"
expect_failure 9.9.10 "$tmp/CodelloySDK-9.9.10.xcframework.zip"
cp "$zip" "$tmp/CodelloySDK-9.9.10.xcframework.zip"
zip10=$tmp/CodelloySDK-9.9.10.xcframework.zip
echo dirty >>"$repo/README.md"
expect_failure 9.9.10 "$zip10"
git -C "$repo" checkout -q README.md

# A commit that fails after the files are written: the script puts both files back.
printf '#!/bin/sh\nexit 1\n' >"$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
expect_failure 9.9.10 "$zip10"
rm "$repo/.git/hooks/pre-commit"

# The example still on the local package: CI of the release commit would fail.
mkdir -p "$repo/Example/CodelloyExample.xcodeproj"
echo 'relativePath = LocalSDK;' >"$repo/Example/CodelloyExample.xcodeproj/project.pbxproj"
git -C "$repo" add Example
git -C "$repo" commit -q -m "example on LocalSDK"
expect_failure 9.9.10 "$zip10"
git -C "$repo" rm -q -r Example
git -C "$repo" commit -q -m "example on the root package"

# Each manifest below is committed, must fail with both files restored, and is then dropped again.
expect_manifest_failure() {
    cp "$1" "$repo/Package.swift"
    git -C "$repo" commit -q -am "manifest case" || fail "the manifest case did not change Package.swift"
    expect_failure 9.9.10 "$zip10"
    git -C "$repo" reset -q --hard HEAD~1
}
good=$tmp/Package.swift.good
cp "$repo/Package.swift" "$good"
zeros=$(printf %064d 0)
# The URL does not come from version.
sed 's|download/\\(version)/CodelloySDK-\\(version)|download/1.0.0/CodelloySDK-1.0.0|' "$good" >"$tmp/m"
expect_manifest_failure "$tmp/m"
# The checksum does not come from checksum.
sed "s/checksum: checksum/checksum: \"$zeros\"/" "$good" >"$tmp/m"
expect_manifest_failure "$tmp/m"
# A second binary target with another URL.
awk -v z="$zeros" '{ print } /^    targets: \[$/ { print "        .binaryTarget(name: \"Other\", url: \"https://example.com/Other.zip\", checksum: \"" z "\")," }' \
    "$good" >"$tmp/m"
expect_manifest_failure "$tmp/m"
# A manifest that does not parse: the error of dump-package is shown.
{ cat "$good"; echo 'let broken: Int = "text"'; } >"$tmp/m"
expect_manifest_failure "$tmp/m"
grep -q 'error:' "$tmp/err" || fail "the error of dump-package is not shown"

# A README without the dependency line.
echo "# No dependency line" >"$repo/README.md"
git -C "$repo" commit -q -am "no dependency line"
expect_failure 9.9.10 "$zip10"

# A newer version that sorts lower as text, so the failures above did not come from the version order.
git -C "$repo" reset -q --hard HEAD~1
"$repo/scripts/update-release.sh" 9.9.10 "$zip10" >"$tmp/out" 2>&1 || fail "9.9.10 after 9.9.9 failed: $(cat "$tmp/out")"

echo "update-release.sh: all checks pass"

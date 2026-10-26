#!/bin/sh
# Sets the version and the SwiftPM checksum of a release in Package.swift and README.md, in one commit.
# Usage: scripts/update-release.sh <version> <path of CodelloySDK-<version>.xcframework.zip>
# The zip comes from one release build of the iOS core. The script does not tag, push or make the GitHub release.
set -eu
# A set CDPATH makes cd print the directory, or go to another folder of the same name.
unset CDPATH

if [ $# -ne 2 ]; then
    echo "Usage: $0 <version> <path of CodelloySDK-<version>.xcframework.zip>" >&2
    exit 1
fi
version=$1
# Only digits and two dots, with digits at each end and between the dots, and no leading zero (semver). 0.0.0 is the
# placeholder, and CI does not check it.
case $version in
    *[!0-9.]* | *.*.*.* | .* | *. | *..* | 0[0-9]* | *.0[0-9]* | 0.0.0) valid=no ;;
    *.*.*) valid=yes ;;
    *) valid=no ;;
esac
if [ $valid = no ]; then
    echo "The version must be major.minor.patch with no leading zero and not 0.0.0, for example 0.1.0." >&2
    exit 1
fi
name=CodelloySDK-$version.xcframework.zip
if [ ! -f "$2" ]; then
    echo "$2 does not exist." >&2
    exit 1
fi
if [ "$(basename "$2")" != "$name" ]; then
    echo "The zip must be named $name, because the release URL in Package.swift uses that name." >&2
    exit 1
fi
zip=$(cd "$(dirname "$2")" && pwd)/$name

cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
    echo "The work tree is not clean. Commit or remove each change first, so that the release commit holds only the release." >&2
    exit 1
fi
if grep -qs 'relativePath = LocalSDK;' Example/CodelloyExample.xcodeproj/project.pbxproj; then
    echo "The example still uses Example/LocalSDK, so CI of the release commit would fail. Move it to the released" \
        "package first (Example/README.md, \"Use the released package\") and commit that change." >&2
    exit 1
fi

version_line='^let version = "[0-9.]*"$'
checksum_line='^let checksum = "[0-9a-f]*"$'
readme_line='codelloy-ios", from: "[0-9.]*")'
for check in "Package.swift:$version_line" "Package.swift:$checksum_line" "README.md:$readme_line"; do
    if ! grep -q "${check#*:}" "${check%%:*}"; then
        echo "${check%%:*} has no line that matches ${check#*:}." >&2
        exit 1
    fi
done
# A version that is not newer would give a released version a second checksum, or move apps back to an older one.
current=$(sed -n "s/^let version = \"\(.*\)\"$/\1/p" Package.swift)
newest=$(printf '%s\n' "$current" "$version" | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)
if [ "$version" = "$current" ] || [ "$newest" != "$version" ]; then
    echo "The version must be newer than the current version $current." >&2
    exit 1
fi

checksum=$(swift package compute-checksum "$zip")
# From here, a failure or an interrupt puts both files back, so that a failed run changes no file.
trap 'rm -f Package.swift.new README.md.new; git reset -q -- Package.swift README.md; git checkout -- Package.swift README.md' EXIT
trap 'exit 1' INT TERM
sed -e "s/$version_line/let version = \"$version\"/" -e "s/$checksum_line/let checksum = \"$checksum\"/" \
    Package.swift >Package.swift.new
sed "s/$readme_line/codelloy-ios\", from: \"$version\")/" README.md >README.md.new
mv Package.swift.new Package.swift
mv README.md.new README.md

# The manifest must still parse and must give exactly one binary URL and one checksum: the new ones.
url=https://github.com/Codelloy/codelloy-ios/releases/download/$version/$name
if ! manifest=$(swift package dump-package 2>&1); then
    echo "$manifest" >&2
    echo "swift package dump-package failed. The script restored both files." >&2
    exit 1
fi
field() { echo "$manifest" | sed -n "s/^ *\"$1\" : \"\(.*\)\",\{0,1\}\$/\1/p"; }
if [ "$(field url)" != "$url" ] || [ "$(field checksum)" != "$checksum" ]; then
    echo "Package.swift does not give exactly one binary target, with $url and checksum $checksum." \
        "The script restored both files." >&2
    exit 1
fi

git add Package.swift README.md
git commit -q -m "chore(release): CodelloySDK $version"
trap - EXIT INT TERM
commit=$(git rev-parse HEAD)

echo "Committed $commit: CodelloySDK $version, checksum $checksum"
cat <<EOF
Next steps, after approval of the release:
1. Push this commit.
2. Check that the zip is still the file of this checksum, then make the release of this commit with it:
   echo "$checksum  $zip" | shasum -a 256 -c
   gh release create $version "$zip" -R Codelloy/codelloy-ios --target $commit --title $version --notes "Codelloy iOS SDK $version"
3. Run the CI of this commit again if it ran before the release. Its resolve step downloads the release zip.
EOF

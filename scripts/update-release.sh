#!/bin/sh
# Sets the version and the SwiftPM checksum of a release in Package.swift and README.md, in one commit.
# Usage: scripts/update-release.sh <version> <path of CodelloySDK-<version>.xcframework.zip>
# The zip comes from one release build of the iOS core. The script does not tag, push or make the GitHub release.
set -eu

if [ $# -ne 2 ]; then
    echo "Usage: $0 <version> <path of CodelloySDK-<version>.xcframework.zip>" >&2
    exit 1
fi
version=$1
# Only digits and two dots, with digits at each end and between the dots.
case $version in
    *[!0-9.]* | *.*.*.* | .* | *. | *..*) valid=no ;;
    *.*.*) valid=yes ;;
    *) valid=no ;;
esac
if [ $valid = no ]; then
    echo "The version must be major.minor.patch, for example 0.1.0." >&2
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

version_line='^let version = "[0-9.]*"$'
checksum_line='^let checksum = "[0-9a-f]*"$'
readme_line='codelloy-ios", from: "[0-9.]*")'
for check in "Package.swift:$version_line" "Package.swift:$checksum_line" "README.md:$readme_line"; do
    if ! grep -q "${check#*:}" "${check%%:*}"; then
        echo "${check%%:*} has no line that matches ${check#*:}." >&2
        exit 1
    fi
done

checksum=$(swift package compute-checksum "$zip")
sed -e "s/$version_line/let version = \"$version\"/" -e "s/$checksum_line/let checksum = \"$checksum\"/" \
    Package.swift >Package.swift.new
sed "s/$readme_line/codelloy-ios\", from: \"$version\")/" README.md >README.md.new
mv Package.swift.new Package.swift
mv README.md.new README.md

# The manifest must still parse and must give the new URL and checksum.
url=https://github.com/Codelloy/codelloy-ios/releases/download/$version/$name
manifest=$(swift package dump-package 2>&1) || manifest=
if ! echo "$manifest" | grep -qF "\"$url\"" || ! echo "$manifest" | grep -qF "\"$checksum\""; then
    git checkout -- Package.swift README.md
    echo "Package.swift does not give $url with checksum $checksum. The script restored both files." >&2
    exit 1
fi

git add Package.swift README.md
git commit -q -m "chore(release): CodelloySDK $version"
commit=$(git rev-parse HEAD)

echo "Committed $commit: CodelloySDK $version, checksum $checksum"
if grep -qs 'relativePath = LocalSDK;' Example/CodelloyExample.xcodeproj/project.pbxproj; then
    echo "The example still uses Example/LocalSDK. Move it to the released package (Example/README.md), or CI fails."
fi
cat <<EOF
Next steps, after approval of the release:
1. Push this commit.
2. Make the release of this commit with this zip:
   gh release create $version "$zip" -R Codelloy/codelloy-ios --target $commit --title $version --notes "Codelloy iOS SDK $version"
3. Run the CI of this commit again if it ran before the release. Its resolve step downloads the release zip.
EOF

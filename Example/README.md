# Codelloy iOS example

A small SwiftUI app that uses the product `CodelloySDK` as an app does. It calls `configure` and `onLink`, gives each URL to `handleLink`, and shows the last link.

## Local values

Git holds only placeholders. Put your values in `Example/Local.xcconfig`, which git ignores:

```sh
cp Example/Local.xcconfig.example Example/Local.xcconfig
```

| Key | Value |
|---|---|
| `DEVELOPMENT_TEAM` | Your Apple Team ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | The bundle ID that the `apple-app-site-association` file of your link domain lists |
| `EXAMPLE_LINK_DOMAIN` | Your link domain, for example `links.example.com` |
| `EXAMPLE_CODELLOY_KEY` | The SDK key of your organisation. Without a key, the app does not call `configure`. |
| `EXAMPLE_CODELLOY_BASE_URL` | Optional. The SDK server. When it is empty, the app uses the default server of the SDK. |

Set the team, the bundle ID and the domain only in `Local.xcconfig`. Do not change them in the Signing & Capabilities tab of Xcode, because Xcode then writes them into files that git tracks.

## The SDK before the first release

No release of the package exists yet. Until the first release, the example uses the local package `Example/LocalSDK`. Its `binaryTarget(path:)` points to `Example/LocalSDK/CodelloySDK.xcframework.zip`, which git ignores. Copy the zip of a release build of the iOS core to that path:

```sh
cp <path of CodelloySDK-<version>.xcframework.zip> Example/LocalSDK/CodelloySDK.xcframework.zip
```

## Build

Simulator build without signing:

```sh
cd Example
xcodebuild -scheme CodelloyExample -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

A link opens the app only in a build that is signed with your Team ID, because the `apple-app-site-association` file lists `<Team ID>.<bundle ID>`. Open `Example/CodelloyExample.xcodeproj` in Xcode and run the scheme `CodelloyExample`.

## Use the released package

At the first release, move the example to the root package of this repo before you run `scripts/update-release.sh`:

1. In `Example/CodelloyExample.xcodeproj/project.pbxproj`, change `relativePath = LocalSDK;` to `relativePath = ..;`.
2. Delete the folder `Example/LocalSDK`.
3. Commit the change.

The example then uses the root `Package.swift`, which is the manifest that apps get. Xcode downloads the release zip and compares it with the checksum. CI builds the example only when `Package.swift` holds a released version.

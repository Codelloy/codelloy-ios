// swift-tools-version: 6.2
import PackageDescription

// Until the first release, the example uses a local build of the SDK: copy a CodelloySDK-<version>.xcframework.zip to
// CodelloySDK.xcframework.zip in this folder (gitignored). Example/README.md tells how to use the released package.
let package = Package(
    name: "LocalSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CodelloySDK", targets: ["CodelloySDK"])
    ],
    targets: [
        .binaryTarget(name: "CodelloySDK", path: "CodelloySDK.xcframework.zip")
    ]
)

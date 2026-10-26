// swift-tools-version: 6.2
// 6.2 is the Swift of the oldest Xcode 26, which builds the XCFramework. An older Swift can fail to read its interface.
import PackageDescription

// scripts/update-release.sh sets both values for each release. 0.0.0 means that no release exists yet.
let version = "0.0.0"
let checksum = "0000000000000000000000000000000000000000000000000000000000000000"

let package = Package(
    name: "CodelloySDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CodelloySDK", targets: ["CodelloySDK"])
    ],
    targets: [
        .binaryTarget(
            name: "CodelloySDK",
            url: "https://github.com/Codelloy/codelloy-ios/releases/download/\(version)/CodelloySDK-\(version).xcframework.zip",
            checksum: checksum
        )
    ]
)

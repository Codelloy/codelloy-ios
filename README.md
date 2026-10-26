# codelloy-ios

The Codelloy iOS SDK for deep links and deferred deep linking, as a Swift package. It needs iOS 15 or later and Xcode 26 or later.

## Install

In Xcode, select File > Add Package Dependencies. Enter `https://github.com/Codelloy/codelloy-ios` and add the product `CodelloySDK` to your app target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Codelloy/codelloy-ios", from: "0.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "CodelloySDK", package: "codelloy-ios")])
]
```

## Set up

```swift
import CodelloySDK
import SwiftUI

@main
struct YourApp: App {
    init() {
        Codelloy.configure(CodelloyConfig(key: "<your pk_live_ or pk_test_ key>"))
        Codelloy.onLink { link in
            // Route the app here. link.url is the deep link, for example shop://product/42.
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in _ = Codelloy.handleLink(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in _ = Codelloy.handleLink(activity) }
        }
    }
}
```

`handleLink` returns `true` for a link on a link domain of your organisation, and the SDK gives the link to `onLink`. It returns `false` for each other URL, and the app handles that URL itself.

## Universal Links

Add the Associated Domains capability to the app target, with one entry for each link domain:

```
applinks:links.example.com
```

Replace `links.example.com` with your link domain. A link that you type in the Safari address bar does not open the app. Tap the link in Notes or Messages to test it.

## Docs

https://codelloy.com/docs/sdks

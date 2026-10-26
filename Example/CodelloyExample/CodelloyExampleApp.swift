import CodelloySDK
import SwiftUI

@main
struct CodelloyExampleApp: App {
    // Example.xcconfig and the gitignored Local.xcconfig give the key and the base URL through Info.plist.
    private static let key = Bundle.main.object(forInfoDictionaryKey: "CodelloyKey") as? String ?? ""

    @State private var link: CodelloyLink?

    init() {
        guard !Self.key.isEmpty else { return }
        let config = CodelloyConfig(key: Self.key)
        // An empty value keeps the default server of the SDK.
        if let text = Bundle.main.object(forInfoDictionaryKey: "CodelloyBaseURL") as? String, let url = URL(string: text) {
            config.baseURL = url
        }
        Codelloy.configure(config)
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                if Self.key.isEmpty {
                    Text("Set EXAMPLE_CODELLOY_KEY in Example/Local.xcconfig.")
                } else if let link {
                    Text(link.url)
                        .textSelection(.enabled)
                    Text(link.isDeferred ? "Deferred link" : "Direct link")
                } else {
                    Text("No link yet. Open a link on your link domain.")
                }
            }
            .padding()
            .onOpenURL { _ = Codelloy.handleLink($0) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { _ = Codelloy.handleLink($0) }
            .task { Codelloy.onLink { link = $0 } }
        }
    }
}

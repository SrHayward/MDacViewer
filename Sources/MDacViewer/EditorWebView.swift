import SwiftUI
import WebKit

/// Hosts the editor + preview web UI, served locally via the `app://` scheme.
struct EditorWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(SchemeHandler(), forURLScheme: "app")
        configuration.userContentController.add(context.coordinator, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true

        context.coordinator.controller.attach(webView)
        if let url = URL(string: "app://mdacviewer/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let controller = WebController()

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "ready" {
                controller.markReady()
                let dark = body["dark"] as? Bool ?? false
                let sync = body["sync"] as? Bool ?? false
                DispatchQueue.main.async {
                    AppState.shared.webReady(dark: dark, sync: sync)
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "app" {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated {
                // Links clicked in the preview open in the user's default browser.
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

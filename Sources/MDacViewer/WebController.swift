import Foundation
import WebKit

/// Thin bridge from Swift to the JavaScript layer running in the web view.
/// Calls made before the web layer signals "ready" are queued and replayed.
final class WebController {
    private weak var webView: WKWebView?
    private(set) var isReady = false
    private var queue: [() -> Void] = []

    func attach(_ webView: WKWebView) {
        self.webView = webView
        AppState.shared.web = self
    }

    func markReady() {
        isReady = true
        let pending = queue
        queue.removeAll()
        pending.forEach { $0() }
    }

    // MARK: - Swift → JavaScript

    func setText(_ text: String) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.setText(\(WebController.jsString(text)))")
        }
    }

    // MARK: - Tabs

    /// Registers a tab's own editor model. The first tab carries over the
    /// editor's boot content (which may hold the first-run sample); later tabs
    /// start fresh.
    func createTab(id: String, text: String? = nil) {
        enqueue { [weak self] in
            let idArg = WebController.jsString(id)
            // nil means "no explicit document": the web layer keeps the
            // editor's boot content for the first tab (the first-run sample),
            // and starts later tabs empty.
            let textArg = text.map { WebController.jsString($0) } ?? "undefined"
            self?.evaluate("window.mdac && window.mdac.createTab(\(idArg), \(textArg))")
        }
    }

    func activateTab(id: String) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.activateTab(\(WebController.jsString(id)))")
        }
    }

    func closeTab(id: String) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.closeTab(\(WebController.jsString(id)))")
        }
    }

    func setText(_ text: String, tabID: String) {
        enqueue { [weak self] in
            let idArg = WebController.jsString(tabID)
            let textArg = WebController.jsString(text)
            self?.evaluate("window.mdac && window.mdac.setTabText(\(idArg), \(textArg))")
        }
    }

    func getText(tabID: String, completion: @escaping (String) -> Void) {
        enqueue { [weak self] in
            self?.webView?.evaluateJavaScript(
                "window.mdac ? window.mdac.getTabText(\(WebController.jsString(tabID))) : \"\""
            ) { result, _ in
                completion((result as? String) ?? "")
            }
        }
    }

    func setTheme(dark: Bool) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.setTheme(\(dark))")
        }
    }

    func setSyncScroll(enabled: Bool) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.setSync(\(enabled))")
        }
    }

    func setPreviewFontSize(_ size: Int) {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.setPreviewFontSize(\(size))")
        }
    }

    func reset() {
        enqueue { [weak self] in
            self?.evaluate("window.mdac && window.mdac.resetEditor()")
        }
    }

    func getText(_ completion: @escaping (String) -> Void) {
        enqueue { [weak self] in
            self?.webView?.evaluateJavaScript("window.mdac ? window.mdac.getText() : \"\"") { result, _ in
                completion((result as? String) ?? "")
            }
        }
    }

    // MARK: - Private

    private func enqueue(_ block: @escaping () -> Void) {
        if isReady {
            block()
        } else {
            queue.append(block)
        }
    }

    private func evaluate(_ javaScript: String) {
        webView?.evaluateJavaScript(javaScript, completionHandler: nil)
    }

    /// Encodes a Swift string safely as a JavaScript string literal.
    static func jsString(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]))
            ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}

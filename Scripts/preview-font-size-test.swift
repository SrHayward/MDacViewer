// Verification harness for the preview text-size feature (run via
// Scripts/verify-preview-font-size.sh, which compiles this file with the app's
// SchemeHandler/State/WebController sources).
//
// It loads the actual Web/ app in a WKWebView and checks three things:
//   1. The preview text resizes, including headings (which scale relative to it).
//   2. The 6px minimum and 72px maximum are enforced by the web layer.
//   3. The chosen size survives a page reload via localStorage.
// It also checks that AppState applies the same clamp and persists the value.

import AppKit
import WebKit

@main
struct PreviewFontSizeTest {
    static var failures = 0
    static var webView: WKWebView!
    static var window: NSWindow!

    static func check(_ condition: Bool, _ label: String) {
        print(condition ? "  ✔ \(label)" : "  ✘ \(label)")
        if !condition { failures += 1 }
    }

    static func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        check(actual == expected, "\(label) (got \(actual), expected \(expected))")
    }

    static func runLoop(for interval: TimeInterval) {
        let end = Date().addingTimeInterval(interval)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// Evaluates JS and waits for the completion handler on the main run loop.
    @discardableResult
    static func evaluate(_ javaScript: String, timeout: TimeInterval = 10) -> Any? {
        var result: Any?
        var finished = false
        webView.evaluateJavaScript(javaScript) { value, error in
            if let error, timeout > 5 {
                print("      JavaScript error: \(error.localizedDescription)")
            }
            result = value
            finished = true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if !finished {
            print("      timed out evaluating: \(javaScript)")
        }
        return result
    }

    static func number(_ javaScript: String) -> Double? {
        (evaluate(javaScript) as? NSNumber)?.doubleValue
    }

    @discardableResult
    static func waitFor(_ description: String,
                        timeout: TimeInterval = 30,
                        condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            runLoop(for: 0.05)
        }
        print("  ✘ timed out waiting for \(description)")
        failures += 1
        return false
    }

    static func loadPage() {
        let configuration = WKWebViewConfiguration()
        // A non-persistent store keeps the test isolated from the real app's
        // settings, while still retaining localStorage across a reload.
        configuration.websiteDataStore = .nonPersistent()

        let webFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Web", isDirectory: true)
        configuration.setURLSchemeHandler(SchemeHandler(baseURL: webFolder), forURLScheme: "app")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700),
                            configuration: configuration)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.contentView = webView
        window.alphaValue = 0 // run invisibly; WebKit still lays out and executes JS
        window.orderFront(nil)
        webView.load(URLRequest(url: URL(string: "app://mdacviewer/index.html")!))
    }

    static func waitForWebReady() {
        waitFor("the web layer to boot", timeout: 30) {
            evaluate("typeof window.mdac === 'object' && typeof window.mdac.setPreviewFontSize === 'function'",
                     timeout: 2) as? Bool == true
        }
    }

    static func currentSize() -> Double? {
        number("parseFloat(getComputedStyle(document.getElementById('output')).fontSize)")
    }

    static func currentHeadingSize() -> Double? {
        number("parseFloat(getComputedStyle(document.querySelector('#output h1')).fontSize)")
    }

    static func testNativeState() {
        print("→ AppState clamps and persists the preview size")
        let defaults = UserDefaults.standard
        let key = "previewFontSize"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let app = AppState.shared
        app.setPreviewFontSize(1)
        checkEqual(app.previewFontSize, 6, "values below 6px clamp to 6")
        checkEqual(defaults.integer(forKey: key), 6, "the clamped size is persisted")

        app.setPreviewFontSize(500)
        checkEqual(app.previewFontSize, 72, "values above 72px clamp to 72")

        app.setPreviewFontSize(24)
        checkEqual(app.previewFontSize, 24, "an in-range value is kept")
        app.increasePreviewFontSize()
        checkEqual(app.previewFontSize, 25, "increase adds 1px")
        app.decreasePreviewFontSize()
        checkEqual(app.previewFontSize, 24, "decrease subtracts 1px")

        app.resetPreviewFontSize()
        checkEqual(app.previewFontSize, 16, "reset returns to the 16px default")
    }

    static func main() {
        let nsapp = NSApplication.shared
        nsapp.setActivationPolicy(.accessory)

        testNativeState()

        print("→ Loading the real web app in WKWebView")
        loadPage()
        waitForWebReady()

        waitFor("the preview to render", timeout: 10) {
            evaluate("document.querySelector('#output h1') !== null", timeout: 2) as? Bool == true
        }

        print("→ Defaults and live resizing")
        checkEqual(currentSize(), 16, "preview starts at 16px")
        checkEqual(currentHeadingSize(), 32, "headings scale with the preview (2em)")

        evaluate("window.mdac.setPreviewFontSize(10)")
        checkEqual(currentSize(), 10, "preview resizes immediately to 10px")
        checkEqual(currentHeadingSize(), 20, "heading resizes with it (2em → 20px)")
        checkEqual(number("window.mdac.getPreviewFontSize()"), 10, "the web API reports 10px")
        checkEqual(evaluate("localStorage.getItem('mdac.previewFontSize')") as? String,
                   "10", "the size is written to localStorage")

        print("→ Range limits")
        evaluate("window.mdac.setPreviewFontSize(2)")
        checkEqual(currentSize(), 6, "2px clamps to the 6px minimum")
        checkEqual(number("window.mdac.getPreviewFontSize()"), 6, "the web API reports the clamped 6px")

        evaluate("window.mdac.setPreviewFontSize(500)")
        checkEqual(currentSize(), 72, "500px clamps to the 72px maximum")

        print("→ Mermaid diagrams still render after resizing")
        evaluate("""
        window.mdac.setText('# Diagram\\n\\n```mermaid\\ngraph TD;\\n  A[Start] --> B[End]\\n```')
        """)
        waitFor("the Mermaid diagram to render", timeout: 15) {
            evaluate("document.querySelector('#output .mermaid svg') !== null", timeout: 2) as? Bool == true
        }
        check(evaluate("document.querySelector('#output .mermaid svg') !== null", timeout: 2) as? Bool == true,
              "a Mermaid diagram renders")
        evaluate("window.mdac.setPreviewFontSize(20)")
        runLoop(for: 1)
        check(evaluate("document.querySelector('#output .mermaid svg') !== null", timeout: 2) as? Bool == true,
              "the diagram still renders after changing the font size")

        print("→ Persistence across a reload")
        evaluate("window.mdac.setPreviewFontSize(23)")
        checkEqual(currentSize(), 23, "preview is 23px before reload")
        evaluate("window.__mdacPreviewFontTest = true")

        webView.reload()
        waitFor("the old page to unload", timeout: 10) {
            evaluate("typeof window.__mdacPreviewFontTest === 'undefined'", timeout: 2) as? Bool == true
        }
        waitForWebReady()
        checkEqual(currentSize(), 23, "the saved 23px size is applied after relaunch")
        checkEqual(number("window.mdac.getPreviewFontSize()"), 23, "the web API reports 23px after reload")

        print()
        if failures == 0 {
            print("RESULT: PASS")
            exit(0)
        } else {
            print("RESULT: FAIL — \(failures) check(s) failed")
            exit(1)
        }
    }
}

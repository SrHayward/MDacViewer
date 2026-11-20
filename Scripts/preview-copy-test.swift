// Verification harness for plain-text copying from the preview
// (run via Scripts/verify-preview-copy.sh, which compiles this file with the
// app's SchemeHandler/WebController sources).
//
// It loads the real Web/ app in a WKWebView, selects rendered Markdown, and
// dispatches a copy event with a DataTransfer. The check that matters: the
// clipboard must contain text/plain only — no text/html carrying the preview's
// code-block background, which is what produced the grey "box" when pasting
// into Claude and other rich-text destinations.

import AppKit
import WebKit

@main
struct PreviewCopyTest {
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

    static func string(_ javaScript: String) -> String? {
        evaluate(javaScript) as? String
    }

    static func bool(_ javaScript: String) -> Bool? {
        evaluate(javaScript) as? Bool
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
        window.alphaValue = 0
        window.orderFront(nil)
        webView.load(URLRequest(url: URL(string: "app://mdacviewer/index.html")!))
    }

    static func waitForWebReady() {
        waitFor("the web layer to boot", timeout: 30) {
            bool("typeof window.mdac === 'object' && window.mdac.isReady === true") == true
        }
    }

    /// Selects the contents of `selector`, dispatches a synthetic copy event,
    /// and returns what our copy handler wrote to the clipboard.
    static func copySelection(of selector: String) -> String? {
        string("""
        (function () {
          var el = document.querySelector(\(WebController.jsString(selector)));
          if (!el) { return JSON.stringify({ error: 'missing element' }); }

          var range = document.createRange();
          range.selectNodeContents(el);
          var selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);

          var clipboard = new DataTransfer();
          var event = new ClipboardEvent('copy', {
            bubbles: true,
            cancelable: true,
            clipboardData: clipboard
          });
          el.dispatchEvent(event);

          return JSON.stringify({
            plain: clipboard.getData('text/plain'),
            html: clipboard.getData('text/html'),
            prevented: event.defaultPrevented
          });
        })()
        """)
    }

    static func parse(_ json: String?) -> [String: Any] {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    static func testCopy() {
        print("→ Copying rendered Markdown produces plain text only")

        let markdown = """
        # Copy test

        Hello **world**, this is a [link](https://example.com) and `inline code`.

        ```swift
        let answer = 42
        print("no box, please")
        ```

        > A quoted line.

        - First item
        - Second item

        | Key | Value |
        | --- | ----- |
        | A   | B     |
        """

        evaluate("window.mdac.setText(\(WebController.jsString(markdown)))")
        waitFor("the copy-test content to render", timeout: 10) {
            evaluate("document.querySelectorAll('#output pre').length === 1", timeout: 2) as? Bool == true
        }

        // The reported bug: a code block copied as rich HTML carries its grey
        // background into Claude. The clipboard must not contain any HTML.
        let code = parse(copySelection(of: "#output pre"))
        checkEqual(code["prevented"] as? Bool, true, "the preview copy handler intercepts the copy")
        checkEqual(code["html"] as? String, "", "a copied code block puts no HTML on the clipboard")
        let codeText = code["plain"] as? String ?? ""
        check(codeText.contains("let answer = 42"), "the copied code block keeps its text")
        check(codeText.contains("print(\"no box, please\")"), "the copied code block keeps every line")
        check(!codeText.contains("<pre"), "the copied code block is not markup")

        let paragraph = parse(copySelection(of: "#output p"))
        checkEqual(paragraph["html"] as? String, "", "a copied paragraph puts no HTML on the clipboard")
        let paragraphText = paragraph["plain"] as? String ?? ""
        check(paragraphText.contains("Hello world"), "the copied paragraph keeps its words")
        check(!paragraphText.contains("background"), "the copied paragraph has no styling")

        let table = parse(copySelection(of: "#output table"))
        checkEqual(table["html"] as? String, "", "a copied table puts no HTML on the clipboard")
        check((table["plain"] as? String ?? "").contains("A\tB"),
              "the copied table keeps rows and columns as text")

        let whole = parse(copySelection(of: "#output"))
        let wholeText = whole["plain"] as? String ?? ""
        checkEqual(whole["html"] as? String, "", "copying the whole preview puts no HTML on the clipboard")
        check(wholeText.contains("Copy test"), "the whole-preview copy includes headings")
        check(wholeText.contains("First item"), "the whole-preview copy includes list text")
        check(!wholeText.contains("<"), "the whole-preview copy contains no tags")

        // Copying outside the preview must not be hijacked: Monaco owns the
        // editor's clipboard behaviour.
        let editor = parse(copySelection(of: "#editor-pane"))
        checkEqual(editor["prevented"] as? Bool, false,
                   "copying in the editor is left to the editor")
    }

    static func main() {
        let nsapp = NSApplication.shared
        nsapp.setActivationPolicy(.accessory)

        loadPage()
        waitForWebReady()

        // The web layer loads the one-off first-run sample just after boot;
        // wait for it so it cannot overwrite the copy-test document.
        waitFor("the first-run sample to settle", timeout: 15) {
            (string("window.mdac.getText()") ?? "").contains("Markdown syntax guide")
        }

        testCopy()

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

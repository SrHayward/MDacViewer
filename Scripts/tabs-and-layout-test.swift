// Verification harness for document tabs and the width-safe preview
// (run via Scripts/verify-tabs-and-layout.sh, which compiles this file with the
// app's SchemeHandler/State/WebController sources).
//
// It loads the real Web/ app in a WKWebView and checks:
//   1. Each tab keeps its own text, active editor model and dirty state.
//   2. Switching tabs swaps the editor content and window title.
//   3. Closing a tab removes its model without disturbing the others.
//   4. Long code lines, URLs and wide tables wrap instead of creating a
//      horizontal scrollbar in the preview.

import AppKit
import WebKit

@main
struct TabsAndLayoutTest {
    static var failures = 0
    static var webView: WKWebView!
    static var window: NSWindow!
    static var controller: WebController!

    static func check(_ condition: Bool, _ label: String) {
        print(condition ? "  ✔ \(label)" : "  ✘ \(label)")
        if !condition { failures += 1 }
    }

    static func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        check(actual == expected, "\(label) (got \(actual), expected \(expected))")
    }

    static func checkFits(_ overflow: Double?, _ label: String) {
        let value = overflow ?? .infinity
        check(value <= 1, "\(label) (overflow \(value) px)")
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
            evaluate("typeof window.mdac === 'object' && window.mdac.isReady === true",
                     timeout: 2) as? Bool == true
        }
    }

    static func write(_ text: String, name: String, in folder: URL) -> URL {
        let url = folder.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func testTabs() {
        print("→ Native tabs drive the web editor models")
        let app = AppState.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdac-tabs-test-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = write("# First\n\nfirst tab text\n", name: "first.md", in: folder)
        let second = write("# Second\n\nsecond tab text\n", name: "second.md", in: folder)

        checkEqual(app.tabs.count, 1, "the app starts with one tab")

        // The first-run syntax guide is loaded by the web layer after boot;
        // it must land in the first tab's model rather than being lost.
        waitFor("the first-run sample to appear in the first tab", timeout: 15) {
            (evaluate("window.mdac.getText().indexOf('Markdown syntax guide') >= 0",
                      timeout: 2) as? Bool) == true
        }
        check(string("window.mdac.getText()")?.contains("Markdown syntax guide") == true,
              "the first-run sample is preserved in the first tab")

        app.open(url: first)
        checkEqual(app.tabs.count, 1, "opening a file reuses the pristine initial tab")
        checkEqual(app.selectedTab?.fileURL?.standardizedFileURL,
                   first.standardizedFileURL, "the first file becomes the selected tab")
        checkEqual(app.windowTitle, "MDacViewer — first.md", "the title names the first file")

        app.open(url: second)
        checkEqual(app.tabs.count, 2, "opening a second file adds a tab")
        checkEqual(app.windowTitle, "MDacViewer — second.md", "the second tab becomes active")

        let firstID = app.tabs[0].jsID
        let secondID = app.tabs[1].jsID

        waitFor("both editor models to be registered", timeout: 10) {
            (evaluate("window.mdac.getTabText('\(secondID)')") as? String) != nil
        }

        checkEqual(string("window.mdac.getActiveTabId()"), secondID,
                   "the web layer's active model is the selected tab")
        check(string("window.mdac.getTabText('\(firstID)')")?.contains("first tab text") == true,
              "the first tab keeps its own text")
        check(string("window.mdac.getTabText('\(secondID)')")?.contains("second tab text") == true,
              "the second tab keeps its own text")
        check(string("window.mdac.getText()")?.contains("second tab text") == true,
              "the editor shows the selected tab's text")

        app.open(url: first)
        checkEqual(app.tabs.count, 2, "reopening an open file does not add a duplicate tab")
        checkEqual(app.selectedTab?.id, app.tabs[0].id,
                   "reopening an open file selects its existing tab")
        app.selectTab(app.tabs[1].id)

        app.selectTab(app.tabs[0].id)
        checkEqual(app.windowTitle, "MDacViewer — first.md",
                   "switching tabs updates the window title")
        checkEqual(string("window.mdac.getActiveTabId()"), firstID,
                   "switching tabs activates the first editor model")
        check(string("window.mdac.getText()")?.contains("first tab text") == true,
              "the editor shows the first tab's text after switching")

        app.markDirty()
        checkEqual(app.windowTitle, "MDacViewer — first.md *",
                   "an edit marks only the selected tab dirty")
        checkEqual(app.tabs.filter { $0.isDirty }.count, 1,
                   "the other tab stays clean")

        app.closeTab(app.tabs[1].id)
        checkEqual(app.tabs.count, 1, "closing a tab removes it")
        checkEqual(string("window.mdac.getTabText('\(secondID)')"), "",
                   "the closed tab's editor model is disposed")
        check(string("window.mdac.getTabText('\(firstID)')")?.contains("first tab text") == true,
              "the remaining tab is untouched")

        app.newTab()
        checkEqual(app.tabs.count, 2, "the + button adds a tab")
        checkEqual(app.selectedTab?.isDirty, false, "a new tab is clean")
        checkEqual(app.windowTitle, "MDacViewer", "a new untitled tab has the plain title")
        checkEqual(app.selectedTab?.fileURL, nil, "the new tab is untitled")

        // Close the clean new tab again through the same data path. Closing a
        // selected tab must select the remaining one.
        app.closeTab(app.tabs[1].id)
        checkEqual(app.tabs.count, 1, "the untitled tab closes cleanly")
        checkEqual(app.selectedTabID, app.tabs[0].id,
                   "closing the selected tab selects the remaining tab")
        checkEqual(app.windowTitle, "MDacViewer — first.md *",
                   "the remaining tab's title and dirty state are kept")
    }

    static func testPreviewWidth() {
        print("→ Preview wraps long content instead of scrolling sideways")
        let longLine = String(repeating: "abcdefghij", count: 80)
        let longURL = "https://example.com/" + String(repeating: "very-long-path-segment/", count: 20)
        let markdown = """
        # Layout

        A long URL: \(longURL)

        ```javascript
        const payload = "\(longLine)";
        ```

        | Key | Value |
        | --- | --- |
        | \(String(repeating: "wide-column-content-", count: 12)) | \(String(repeating: "more-content-", count: 12)) |
        """

        evaluate("window.mdac.setText(\(WebController.jsString(markdown)))")
        waitFor("the layout test content to render", timeout: 10) {
            evaluate("document.querySelectorAll('#output pre').length === 1", timeout: 2) as? Bool == true
        }

        let paneFits = number("""
        (function () {
          var pane = document.getElementById('preview-pane');
          return pane.scrollWidth - pane.clientWidth;
        })()
        """)
        checkFits(paneFits, "the preview pane has no horizontal overflow")

        let outputFits = number("""
        (function () {
          var output = document.getElementById('output');
          return output.scrollWidth - output.clientWidth;
        })()
        """)
        checkFits(outputFits, "the rendered content fits the preview width")

        let preFits = number("""
        (function () {
          var pre = document.querySelector('#output pre');
          return pre.scrollWidth - pre.clientWidth;
        })()
        """)
        checkFits(preFits, "a long code block wraps to the pane width")

        let preStyle = string("""
        (function () {
          var style = getComputedStyle(document.querySelector('#output pre'));
          return style.whiteSpace + '|' + style.overflowX;
        })()
        """)
        checkEqual(preStyle, "pre-wrap|hidden",
                   "code blocks are configured to wrap without a scrollbar")

        let tableFits = number("""
        (function () {
          var table = document.querySelector('#output table');
          return table.scrollWidth - table.clientWidth;
        })()
        """)
        checkFits(tableFits, "a wide table fits the preview width")

        let inlineFits = number("""
        (function () {
          var link = document.querySelector('#output a');
          return link.scrollWidth - link.clientWidth;
        })()
        """)
        checkFits(inlineFits, "a long URL wraps rather than widening the pane")
    }

    static func main() {
        let nsapp = NSApplication.shared
        nsapp.setActivationPolicy(.accessory)

        loadPage()
        waitForWebReady()

        // Wire the real Swift bridge to this web view, exactly like the app.
        controller = WebController()
        controller.attach(webView)
        controller.markReady()
        let app = AppState.shared
        app.webReady(dark: false, sync: false, previewFontSize: 16)

        testTabs()
        testPreviewWidth()

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

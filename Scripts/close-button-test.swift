// Regression harness for the red-close-button crash (run via
// Scripts/verify-close-button.sh, which compiles this file with the app's
// WindowFrameSaver/State/WebController sources).
//
// The 1.0.2 bug: WindowFrameSaver replaces the close button's action with its
// own closeButtonPressed and, when there was nothing to save, called
// performClose(nil). performClose simulates a click on that very button, so
// the action fired again and again (the crash report shows ~10,000 recursive
// closeButtonPressed frames) until the main thread's stack overflowed.
//
// Clicking the button here is programmatic, so no Accessibility permission and
// no running app is needed: this process either closes the window (pass) or
// dies with the same stack-overflow crash (fail).

import AppKit

@main
struct CloseButtonTest {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        print(condition ? "  ✔ \(label)" : "  ✘ \(label)")
        if !condition { failures += 1 }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // 1. A click with nothing to save must close the window — not recurse.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.makeKeyAndOrderFront(nil)

        let coordinator = WindowFrameSaver.Coordinator()
        coordinator.attach(to: window)

        guard let closeButton = window.standardWindowButton(.closeButton) else {
            print("  ✘ could not find the standard close button")
            exit(1)
        }
        check(closeButton.target === coordinator, "WindowFrameSaver intercepts the close button")
        check(window.isVisible, "window is visible before the click")
        closeButton.performClick(nil)
        check(!window.isVisible, "clicking close closes the window (no recursion crash)")

        // 2. Untitled text typed in a fresh session counts as unsaved.
        let state = AppState.shared
        check(state.windowTitle == "MDacViewer", "fresh session title is exactly \"MDacViewer\"")
        check(!state.isDirty, "fresh session is not dirty")
        state.markDirty()
        check(state.isDirty, "an edit marks the document dirty with no file open")
        check(state.windowTitle == "MDacViewer *",
              "title shows the unsaved-changes asterisk (got \"\(state.windowTitle)\")")

        // 3. Opening a file names the title and clears the asterisk; editing
        //    again puts it back after the file name.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdac-close-test-\(getpid()).md")
        try? "# hi\n".write(to: file, atomically: true, encoding: .utf8)
        state.open(url: file)
        check(state.currentFileURL == file, "opening a file records it as the current file")
        check(!state.isDirty, "opening a file clears the unsaved flag")
        check(state.windowTitle == "MDacViewer — \(file.lastPathComponent)",
              "title names the open file (got \"\(state.windowTitle)\")")
        state.markDirty()
        check(state.windowTitle == "MDacViewer — \(file.lastPathComponent) *",
              "editing an open file puts the asterisk after the file name")
        try? FileManager.default.removeItem(at: file)

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
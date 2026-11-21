import SwiftUI
import AppKit

@main
struct MDacViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("MDacViewer", id: "main") {
            MainWindow()
                .environmentObject(app)
        }
        .commands {
            // Replace the standard About panel with our own — it shows the
            // version and a manual "Check for Updates" action.
            CommandGroup(replacing: .appInfo) {
                Button("About MDacViewer") { openWindow(id: "about") }
            }

            // This app is a single window; the replacement for "New" is a new
            // document tab inside it.
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { app.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Open…") { app.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { app.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { app.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Close Tab") { app.closeCurrentTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Markdown") { app.copyAll() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Reset Editor…") { app.requestReset() }
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Toggle(ViewMode.editorOnly.menuTitle, isOn: viewModeBinding(.editorOnly))
                    .keyboardShortcut("1", modifiers: .command)
                Toggle(ViewMode.split.menuTitle, isOn: viewModeBinding(.split))
                    .keyboardShortcut("2", modifiers: .command)
                Toggle(ViewMode.previewOnly.menuTitle, isOn: viewModeBinding(.previewOnly))
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Toggle("Sync Scrolling", isOn: $app.syncScroll)
                    .disabled(app.viewMode != .split)
                Toggle("Dark Mode", isOn: $app.darkMode)
                Divider()
                Button("Increase Preview Text Size") { app.increasePreviewFontSize() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Preview Text Size") { app.decreasePreviewFontSize() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Reset Preview Text Size") { app.resetPreviewFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Window("About MDacViewer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }

    /// Menu-item binding for a mutually exclusive view mode: selecting the
    /// checked item must not turn the layout off, so only `true` is applied.
    private func viewModeBinding(_ mode: ViewMode) -> Binding<Bool> {
        Binding(
            get: { app.viewMode == mode },
            set: { isOn in
                if isOn { app.viewMode = mode }
            }
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateChecker.shared.start()
    }

    // Handles "Open With MDacViewer" / double-click on a .md file in Finder.
    // Each file becomes its own tab.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppState.shared.open(url: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // ⌘Q with unsaved changes in an open file: show the same Save / Cancel /
    // Don't Save nudge as closing the window, and only then allow termination.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let app = AppState.shared
        if app.closeApproved || !app.isDirty {
            return .terminateNow
        }
        let window = sender.mainWindow ?? sender.windows.first
        app.confirmClose(window: window) { proceed in
            // Reply on the next run loop turn, never inside this call.
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: proceed)
            }
        }
        return .terminateLater
    }
}

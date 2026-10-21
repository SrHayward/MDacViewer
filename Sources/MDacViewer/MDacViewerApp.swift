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

            // Remove the default "New" item — this app is a single window.
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .newItem) {
                Button("Open…") { app.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { app.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { app.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Markdown") { app.copyAll() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Reset Editor…") { app.requestReset() }
            }
        }

        Window("About MDacViewer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateChecker.shared.start()
    }

    // Handles "Open With MDacViewer" / double-click on a .md file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppState.shared.open(url: url)
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

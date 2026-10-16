import SwiftUI
import AppKit

@main
struct MDacViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("MDacViewer", id: "main") {
            MainWindow()
                .environmentObject(app)
        }
        .commands {
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Handles "Open With MDacViewer" / double-click on a .md file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppState.shared.open(url: url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

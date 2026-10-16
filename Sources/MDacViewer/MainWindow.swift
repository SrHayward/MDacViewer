import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        EditorWebView()
            .frame(minWidth: 880, minHeight: 540)
            .background(WindowFrameSaver())
            .navigationTitle(app.windowTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { app.openDocument() } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .help("Open a Markdown file (⌘O)")

                    Button { app.saveDocument() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save (⌘S) — saves to the opened file, or asks where to save")

                    Button { app.copyAll() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy the full Markdown source (⇧⌘C)")

                    Button { app.requestReset() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .help("Clear the editor")
                }

                ToolbarItemGroup {
                    HStack(spacing: 8) {
                        Text("Sync scroll")
                        Toggle("Sync scroll", isOn: $app.syncScroll)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .help("Keep the editor and preview scrolled together")

                    HStack(spacing: 8) {
                        Text("Dark mode")
                        Toggle("Dark mode", isOn: $app.darkMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .help("Switch between light and dark appearance")

                    Button { app.openRepo() } label: {
                        Image(nsImage: Self.githubMark)
                            .renderingMode(.template)
                    }
                    .help("View source on GitHub")
                }
            }
            .onReceive(app.$darkMode.dropFirst()) { _ in app.pushSettingsToWeb() }
            .onReceive(app.$syncScroll.dropFirst()) { _ in app.pushSettingsToWeb() }
            .alert("Reset editor?", isPresented: $app.showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { app.performReset() }
            } message: {
                Text("Are you sure you want to reset? This will clear the editor and any unsaved text.")
            }
    }

    static let githubMark: NSImage = {
        if let url = Bundle.main.url(forResource: "github-mark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "GitHub")
            ?? NSImage()
    }()
}

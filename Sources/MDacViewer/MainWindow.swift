import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showingTextSize = false

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

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 24) {
                        HStack(spacing: 8) {
                            Text("Sync scroll")
                            Toggle("Sync scroll", isOn: $app.syncScroll)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .help("Keep the editor and preview scrolled together")

                        HStack(spacing: 8) {
                            Text("Dark mode")
                            Toggle("Dark mode", isOn: $app.darkMode)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .help("Switch between light and dark appearance")

                        Button { showingTextSize.toggle() } label: {
                            Image(systemName: "textformat.size")
                        }
                        .help("Preview text size (⌘+ / ⌘−)")
                        .accessibilityLabel("Preview text size")
                        .popover(isPresented: $showingTextSize, arrowEdge: .bottom) {
                            PreviewTextSizePopover(app: app)
                        }

                        if updates.updateAvailable {
                            Button { updates.openReleasesPage() } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .help("Update available")
                            .accessibilityLabel("Update available")
                            .transition(.opacity)
                        }

                        Button { app.openRepo() } label: {
                            Image(nsImage: Self.githubMark)
                                .renderingMode(.template)
                        }
                        .help("View source on GitHub")
                    }
                    .padding(.horizontal, 10)
                    .animation(.easeInOut(duration: 0.25), value: updates.updateAvailable)
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

/// Toolbar popover for adjusting only the rendered preview's text size.
private struct PreviewTextSizePopover: View {
    @ObservedObject var app: AppState

    private var size: Binding<Double> {
        Binding(
            get: { Double(app.previewFontSize) },
            set: { app.setPreviewFontSize(Int($0.rounded())) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview text size")
                    .font(.headline)
                Spacer()
                Text("\(app.previewFontSize) px")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("6")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Slider(value: size,
                       in: Double(AppState.minPreviewFontSize)...Double(AppState.maxPreviewFontSize),
                       step: 1)
                    .accessibilityLabel("Preview text size")
                Text("72")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Stepper("", value: size,
                        in: Double(AppState.minPreviewFontSize)...Double(AppState.maxPreviewFontSize),
                        step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Preview text size")
            }

            HStack {
                Text("Saved for next time")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Reset") { app.resetPreviewFontSize() }
                    .disabled(app.previewFontSize == AppState.defaultPreviewFontSize)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showingTextSize = false
    @State private var showingViewMode = false

    var body: some View {
        VStack(spacing: 0) {
            DocumentTabBar(app: app)
            EditorWebView()
                .overlay(alignment: .topTrailing) {
                    if let version = updates.pendingAnnouncementVersion {
                        UpdateAvailableCard(version: version, updates: updates)
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25),
                           value: updates.pendingAnnouncementVersion)
        }
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
                        Toggle(isOn: $app.syncScroll) {
                            Label("Sync scroll",
                                  systemImage: app.syncScroll
                                      ? "arrow.up.and.down.circle.fill"
                                      : "arrow.up.and.down.circle")
                        }
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                        .controlSize(.regular)
                        .disabled(app.viewMode != .split)
                        .help(app.viewMode == .split
                              ? "Sync scroll: \(app.syncScroll ? "On" : "Off")"
                              : "Sync scroll (available in Split view)")
                        .accessibilityLabel("Sync scroll")

                        Toggle(isOn: $app.darkMode) {
                            Label("Dark mode",
                                  systemImage: app.darkMode ? "moon.fill" : "moon")
                        }
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                        .controlSize(.regular)
                        .help("Dark mode: \(app.darkMode ? "On" : "Off")")
                        .accessibilityLabel("Dark mode")

                        Button { showingViewMode.toggle() } label: {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        .help("View mode: \(app.viewMode.menuTitle) (⌘1 / ⌘2 / ⌘3)")
                        .accessibilityLabel("View mode")
                        .popover(isPresented: $showingViewMode, arrowEdge: .bottom) {
                            ViewModePopover(app: app, isPresented: $showingViewMode)
                        }

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
                Text("Are you sure you want to reset? This will clear the editor and any unsaved text in the current tab.")
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

/// Floating notice shown over the editor when a newer release is detected.
/// Dismissal is remembered per version by ``UpdateChecker``.
private struct UpdateAvailableCard: View {
    let version: String
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.callout.weight(.semibold))
                Text("Version \(version) is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Download") {
                updates.downloadAnnouncedUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Download version \(version)")

            Button {
                updates.dismissAnnouncement()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help("Dismiss")
            .accessibilityLabel("Dismiss update notification")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
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

/// Toolbar popover for choosing which pane(s) the editor area shows.
private struct ViewModePopover: View {
    @ObservedObject var app: AppState
    @Binding var isPresented: Bool
    @State private var hovering: ViewMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("View mode")
                .font(.headline)

            VStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    Button {
                        app.viewMode = mode
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 14)
                                .opacity(app.viewMode == mode ? 1 : 0)

                            Image(systemName: mode.symbolName)
                                .font(.system(size: 13))
                                .foregroundStyle(app.viewMode == mode
                                                 ? Color.accentColor
                                                 : Color.secondary)
                                .frame(width: 22)

                            Text(mode.menuTitle)
                                .font(.system(size: 13))

                            Spacer(minLength: 12)

                            Text(mode.shortcutLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(rowBackground(for: mode))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside {
                            hovering = mode
                        } else if hovering == mode {
                            hovering = nil
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func rowBackground(for mode: ViewMode) -> Color {
        if app.viewMode == mode { return Color.accentColor.opacity(0.16) }
        if hovering == mode { return Color.primary.opacity(0.07) }
        return .clear
    }
}

private extension ViewMode {
    var symbolName: String {
        switch self {
        case .editorOnly: return "chevron.left.forwardslash.chevron.right"
        case .split: return "rectangle.split.2x1"
        case .previewOnly: return "eye"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .editorOnly: return "⌘1"
        case .split: return "⌘2"
        case .previewOnly: return "⌘3"
        }
    }
}

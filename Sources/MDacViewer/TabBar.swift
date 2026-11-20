import SwiftUI
import AppKit

/// Browser-style strip of open documents above the editor, styled after
/// Sublime Text: flat square tabs, the active tab clearly stands out against
/// dimmed inactive tabs, and the close button only shows on the active or
/// hovered tab.
struct DocumentTabBar: View {
    @ObservedObject var app: AppState
    @State private var draggingTabID: UUID?
    @State private var dropTargetID: UUID?

    private var palette: TabBarPalette { TabBarPalette(dark: app.darkMode) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabButton(
                        app: app,
                        tab: tab,
                        palette: palette,
                        showsLeadingDivider: showsDivider(before: index),
                        draggingTabID: $draggingTabID,
                        dropTargetID: $dropTargetID
                    )
                }

                NewTabButton(palette: palette) { app.newTab() }
                    .padding(.leading, 4)
            }
            .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: TabBarPalette.tabHeight, alignment: .bottom)
        // The window controls' glass capsule floats over the top of the
        // content view. Without this inset the first tab starts underneath it
        // (and its shadow), which makes the tab look like it bleeds into the
        // titlebar. The strip colour fills the inset.
        .padding(.top, TabBarPalette.topInset)
        .frame(height: TabBarPalette.height, alignment: .bottom)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                palette.strip
                Rectangle()
                    .fill(palette.bottomBorder)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .top) {
            // A clear separator between the window toolbar and the strip.
            // A hairline was not enough: in light mode the white tab met the
            // white toolbar, and in dark mode the dark tab met the dark
            // toolbar, so the active tab still looked like it bled into the
            // window chrome. Two pixels of contrast stop that.
            Rectangle()
                .fill(palette.topBorder)
                .frame(height: 2)
        }
    }

    /// Sublime hides the separators that touch the active tab, so the selected
    /// tab reads as one continuous surface with the editor below it.
    private func showsDivider(before index: Int) -> Bool {
        guard index > 0, app.tabs.indices.contains(index) else { return false }
        return app.tabs[index].id != app.selectedTabID
            && app.tabs[index - 1].id != app.selectedTabID
    }
}

private struct TabButton: View {
    @ObservedObject var app: AppState
    let tab: DocumentTab
    let palette: TabBarPalette
    let showsLeadingDivider: Bool
    @Binding var draggingTabID: UUID?
    @Binding var dropTargetID: UUID?

    @State private var hovering = false

    private var isSelected: Bool { app.selectedTabID == tab.id }
    private var showsCloseButton: Bool { isSelected || hovering }
    private var showsDropIndicator: Bool {
        dropTargetID == tab.id && draggingTabID != nil && draggingTabID != tab.id
    }

    /// Whether the dragged tab is coming from the left. The indicator sits on
    /// the trailing edge for a rightward drag and the leading edge for a
    /// leftward one, matching where the tab will land.
    private var dropsAfter: Bool {
        guard let draggingTabID,
              let source = app.tabs.firstIndex(where: { $0.id == draggingTabID }),
              let target = app.tabs.firstIndex(where: { $0.id == tab.id }) else {
            return false
        }
        return source < target
    }

    private var background: Color {
        if isSelected { return palette.active }
        return hovering ? palette.inactiveHover : palette.inactive
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayName)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? palette.activeText : palette.inactiveText)
                .lineLimit(1)
                .truncationMode(.middle)

            if tab.isDirty {
                Circle()
                    .fill(isSelected ? palette.activeText : palette.inactiveText)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Unsaved changes")
            }

            Button { app.closeTab(tab.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? palette.activeText : palette.inactiveText)
            .opacity(showsCloseButton ? 0.75 : 0)
            .allowsHitTesting(showsCloseButton)
            .help("Close tab")
            .accessibilityLabel("Close \(tab.displayName)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: TabBarPalette.tabHeight)
        .frame(minWidth: 100, maxWidth: 220)
        .background(background)
        .overlay(alignment: .leading) {
            if showsLeadingDivider {
                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.selectTab(tab.id) }
        .onHover { hovering = $0 }
        .help(tab.fileURL?.path ?? tab.displayName)
        .onDrag {
            draggingTabID = tab.id
            dropTargetID = nil
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(
            targetID: tab.id,
            draggingTabID: $draggingTabID,
            dropTargetID: $dropTargetID,
            app: app
        ))
        .overlay {
            if showsDropIndicator {
                HStack(spacing: 0) {
                    if dropsAfter { Spacer(minLength: 0) }
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                    if !dropsAfter { Spacer(minLength: 0) }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Accepts a dragged tab and reorders the strip when it is dropped. The
/// indicator is shown in `TabButton` while `dropTargetID` points at it.
private struct TabDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingTabID: UUID?
    @Binding var dropTargetID: UUID?
    let app: AppState

    func dropEntered(info: DropInfo) {
        guard draggingTabID != nil else { return }
        dropTargetID = targetID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID { dropTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingTabID = nil
            dropTargetID = nil
        }
        guard let draggedID = draggingTabID,
              draggedID != targetID,
              let source = app.tabs.firstIndex(where: { $0.id == draggedID }),
              let destination = app.tabs.firstIndex(where: { $0.id == targetID })
        else { return false }

        withAnimation(.easeInOut(duration: 0.15)) {
            app.moveTab(from: source, to: destination)
        }
        return true
    }
}

private struct NewTabButton: View {
    let palette: TabBarPalette
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.inactiveText)
                .frame(width: 30, height: TabBarPalette.tabHeight)
                .background(hovering ? palette.inactiveHover : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New tab (⌘T)")
        .accessibilityLabel("New tab")
    }
}

/// Colours for the Sublime-style tab strip. Light mode mirrors Sublime's
/// default light theme (grey strip, dimmed tabs, white active tab). In dark
/// mode the active tab uses the editor's background, while inactive tabs are a
/// clearly lighter grey so the selected tab reads as the dark notch connected
/// to the content below.
struct TabBarPalette {
    /// Height of one tab.
    static let tabHeight: CGFloat = 32
    /// Strip-coloured breathing room above the tabs, below the window controls.
    static let topInset: CGFloat = 6
    /// Full height of the strip (tab + inset).
    static let height: CGFloat = tabHeight + topInset

    let strip: Color
    let inactive: Color
    let inactiveHover: Color
    let active: Color
    let divider: Color
    let topBorder: Color
    let bottomBorder: Color
    let inactiveText: Color
    let activeText: Color

    init(dark: Bool) {
        if dark {
            strip = Color(red: 0.09, green: 0.09, blue: 0.09)
            inactive = Color(red: 0.25, green: 0.25, blue: 0.25)
            inactiveHover = Color(red: 0.30, green: 0.30, blue: 0.30)
            // The active tab uses the editor's own background (#1e1e1e), so it
            // reads as one continuous surface with the content below — exactly
            // as it does in light mode, where the tab is white.
            active = Color(red: 0.118, green: 0.118, blue: 0.118)
            divider = Color(red: 0.06, green: 0.06, blue: 0.06)
            topBorder = Color(red: 0.23, green: 0.23, blue: 0.23)
            bottomBorder = Color(red: 0.04, green: 0.04, blue: 0.04)
            inactiveText = Color(red: 0.72, green: 0.72, blue: 0.72)
            activeText = Color(red: 0.96, green: 0.96, blue: 0.96)
        } else {
            strip = Color(red: 0.80, green: 0.80, blue: 0.80)
            inactive = Color(red: 0.87, green: 0.87, blue: 0.87)
            inactiveHover = Color(red: 0.92, green: 0.92, blue: 0.92)
            active = .white
            divider = Color(red: 0.73, green: 0.73, blue: 0.73)
            topBorder = Color(red: 0.68, green: 0.68, blue: 0.68)
            bottomBorder = Color(red: 0.69, green: 0.69, blue: 0.69)
            inactiveText = Color(red: 0.36, green: 0.36, blue: 0.36)
            activeText = Color(red: 0.09, green: 0.09, blue: 0.09)
        }
    }
}

import SwiftUI
import AppKit

/// Browser-style strip of open documents above the editor, styled after
/// Sublime Text: flat square tabs, the active tab clearly stands out against
/// dimmed inactive tabs, and the close button only shows on the active or
/// hovered tab.
struct DocumentTabBar: View {
    @ObservedObject var app: AppState

    private var palette: TabBarPalette { TabBarPalette(dark: app.darkMode) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(app.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabButton(
                            app: app,
                            tab: tab,
                            palette: palette,
                            showsLeadingDivider: showsDivider(before: index)
                        )
                    }
                }
                .padding(.leading, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NewTabButton(palette: palette) { app.newTab() }
        }
        .frame(height: TabBarPalette.height)
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

    @State private var hovering = false

    private var isSelected: Bool { app.selectedTabID == tab.id }
    private var showsCloseButton: Bool { isSelected || hovering }

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
        .frame(height: TabBarPalette.height)
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
                .frame(width: 30, height: TabBarPalette.height)
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
/// default light theme exactly (grey strip, dimmed tabs, white active tab);
/// dark mode keeps the same relationship — active lightest, inactive dimmed,
/// strip darkest — so the active tab is obvious in both appearances.
struct TabBarPalette {
    static let height: CGFloat = 32

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
            inactive = Color(red: 0.17, green: 0.17, blue: 0.17)
            inactiveHover = Color(red: 0.21, green: 0.21, blue: 0.21)
            // The active tab uses the editor's own background (#1e1e1e), so it
            // reads as one continuous surface with the content below — exactly
            // as it does in light mode, where the tab is white.
            active = Color(red: 0.118, green: 0.118, blue: 0.118)
            divider = Color(red: 0.06, green: 0.06, blue: 0.06)
            topBorder = Color(red: 0.23, green: 0.23, blue: 0.23)
            bottomBorder = Color(red: 0.04, green: 0.04, blue: 0.04)
            inactiveText = Color(red: 0.62, green: 0.62, blue: 0.62)
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

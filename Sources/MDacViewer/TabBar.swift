import SwiftUI
import AppKit

/// Browser-style strip of open documents above the editor.
struct DocumentTabBar: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(app.tabs) { tab in
                    TabButton(app: app, tab: tab)
                }

                Button { app.newTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tab (⌘T)")
                .accessibilityLabel("New tab")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }
}

private struct TabButton: View {
    @ObservedObject var app: AppState
    let tab: DocumentTab

    private var isSelected: Bool { app.selectedTabID == tab.id }

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            if tab.isDirty {
                Circle()
                    .fill(Color.secondary)
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
            .foregroundStyle(.secondary)
            .opacity(isSelected ? 1 : 0.55)
            .help("Close tab")
            .accessibilityLabel("Close \(tab.displayName)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 26)
        .frame(minWidth: 110, maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor),
                              lineWidth: isSelected ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selectTab(tab.id) }
        .help(tab.fileURL?.path ?? tab.displayName)
    }
}

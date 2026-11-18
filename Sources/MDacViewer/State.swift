import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One document open in the window's tab bar. The text itself lives in the web
/// layer — each tab has its own Monaco model, so switching tabs preserves the
/// text, undo history and scroll position — while this value tracks the file
/// link and unsaved state.
struct DocumentTab: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL?
    var isDirty = false
    /// Text queued while the web layer is still booting (for example a file
    /// opened through Finder before the window has finished loading).
    var pendingText: String?

    var jsID: String { id.uuidString }

    var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }
}

/// App-wide state, bridged between the native toolbar/menus and the web editor.
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let darkModeKey = "darkMode"
    private static let previewFontSizeKey = "previewFontSize"

    static let minPreviewFontSize = 6
    static let maxPreviewFontSize = 72
    static let defaultPreviewFontSize = 16

    @Published var darkMode = false
    @Published var syncScroll = false
    @Published var windowTitle = "MDacViewer"
    @Published var showResetConfirm = false

    /// The window's open documents, in tab order.
    @Published private(set) var tabs: [DocumentTab]
    @Published private(set) var selectedTabID: UUID

    /// Preview pane text size in points (CSS pixels), adjustable from 6px.
    /// Persisted here and mirrored to the web layer's localStorage.
    @Published private(set) var previewFontSize: Int = 16 {
        didSet {
            guard previewFontSize != oldValue else { return }
            UserDefaults.standard.set(previewFontSize, forKey: Self.previewFontSizeKey)
            web?.setPreviewFontSize(previewFontSize)
        }
    }

    /// Set once the user has approved closing (Save or Don't Save), so the
    /// window-close and app-quit paths do not ask a second time.
    private(set) var closeApproved = false
    private var isNudging = false

    weak var web: WebController?

    private init() {
        let firstTab = DocumentTab(id: UUID())
        tabs = [firstTab]
        selectedTabID = firstTab.id

        darkMode = UserDefaults.standard.bool(forKey: Self.darkModeKey)
        let storedFontSize = UserDefaults.standard.integer(forKey: Self.previewFontSizeKey)
        previewFontSize = storedFontSize == 0
            ? Self.defaultPreviewFontSize
            : Self.clampedPreviewFontSize(storedFontSize)
        applyAppearance()
    }

    // MARK: - Tabs

    var selectedTab: DocumentTab? {
        tabs.first { $0.id == selectedTabID }
    }

    /// True while *any* open document has unsaved edits. Closing the window or
    /// quitting prompts for every dirty tab, not just the visible one.
    var isDirty: Bool {
        tabs.contains { $0.isDirty }
    }

    var currentFileURL: URL? {
        selectedTab?.fileURL
    }

    /// Adds an empty tab and makes it active.
    func newTab() {
        let tab = DocumentTab(id: UUID())
        tabs.append(tab)
        selectedTabID = tab.id
        refreshWindowTitle()

        if let web, web.isReady {
            web.createTab(id: tab.jsID)
            web.activateTab(id: tab.jsID)
        }
    }

    func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        refreshWindowTitle()
        if let web, web.isReady {
            web.activateTab(id: tab.jsID)
        }
    }

    /// Closes a tab, asking about unsaved changes first. The window always
    /// keeps at least one (empty) tab.
    func closeTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let finish: (Bool) -> Void = { [weak self] proceed in
            guard proceed else { return }
            self?.removeTab(id)
        }

        if tab.isDirty {
            promptSave(tabID: id, window: NSApp.keyWindow, completion: finish)
        } else {
            finish(true)
        }
    }

    func closeCurrentTab() {
        closeTab(selectedTabID)
    }

    private func removeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        let removed = tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = DocumentTab(id: UUID())
            tabs = [replacement]
            selectedTabID = replacement.id
            if let web, web.isReady {
                web.createTab(id: replacement.jsID)
                web.activateTab(id: replacement.jsID)
            }
        } else if wasSelected {
            let replacement = tabs[min(index, tabs.count - 1)]
            selectedTabID = replacement.id
            if let web, web.isReady {
                web.activateTab(id: replacement.jsID)
            }
        }

        if let web, web.isReady {
            web.closeTab(id: removed.jsID)
        }
        refreshWindowTitle()
    }

    // MARK: - Settings

    /// Push the current toggle states into the web layer (idempotent) and
    /// apply the app-wide appearance so the window chrome matches too.
    func pushSettingsToWeb() {
        web?.setTheme(dark: darkMode)
        web?.setSyncScroll(enabled: syncScroll)
        web?.setPreviewFontSize(previewFontSize)
        UserDefaults.standard.set(darkMode, forKey: Self.darkModeKey)
        applyAppearance()
    }

    // MARK: - Preview text size

    func setPreviewFontSize(_ size: Int) {
        previewFontSize = Self.clampedPreviewFontSize(size)
    }

    func increasePreviewFontSize() {
        setPreviewFontSize(previewFontSize + 1)
    }

    func decreasePreviewFontSize() {
        setPreviewFontSize(previewFontSize - 1)
    }

    func resetPreviewFontSize() {
        setPreviewFontSize(Self.defaultPreviewFontSize)
    }

    static func clampedPreviewFontSize(_ size: Int) -> Int {
        min(maxPreviewFontSize, max(minPreviewFontSize, size))
    }

    /// Switches the entire app — title bar, toolbar, menus and panes — between
    /// light and dark, following the in-app Dark mode toggle.
    func applyAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
    }

    /// Called by the web layer once it has booted, reporting its persisted
    /// settings. Registers every open tab with the web layer at this point:
    /// tab calls made earlier are kept in `pendingText`.
    func webReady(dark: Bool, sync: Bool, previewFontSize: Int) {
        darkMode = dark
        syncScroll = sync
        self.previewFontSize = Self.clampedPreviewFontSize(previewFontSize)

        if let web {
            if let first = tabs.first {
                // No pending text means the first tab should keep the web
                // layer's boot content (the one-off first-run sample).
                web.createTab(id: first.jsID, text: first.pendingText)
                for tab in tabs.dropFirst() {
                    web.createTab(id: tab.jsID, text: tab.pendingText ?? "")
                }
            }
            if let selected = selectedTab {
                web.activateTab(id: selected.jsID)
            }
        }

        for index in tabs.indices {
            tabs[index].pendingText = nil
        }
        pushSettingsToWeb()
    }

    // MARK: - Open

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.markdownTypes
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.open(url: url)
            }
        }
    }

    func open(url: URL) {
        do {
            let text = try Self.readText(at: url)

            // Already open? Bring its tab forward instead of duplicating it.
            if let existing = tabs.first(where: {
                $0.fileURL?.standardizedFileURL == url.standardizedFileURL
            }) {
                selectTab(existing.id)
                return
            }

            let webIsReady = web?.isReady == true

            // Reuse a pristine untitled tab, otherwise open a new tab.
            if let active = selectedTab, active.fileURL == nil, !active.isDirty,
               let index = tabs.firstIndex(where: { $0.id == active.id }) {
                tabs[index].fileURL = url
                tabs[index].isDirty = false
                if webIsReady, let web {
                    web.setText(text, tabID: active.jsID)
                } else {
                    tabs[index].pendingText = text
                }
                selectedTabID = active.id
            } else {
                var tab = DocumentTab(id: UUID(), fileURL: url)
                if !webIsReady {
                    tab.pendingText = text
                }
                tabs.append(tab)
                selectedTabID = tab.id
                if webIsReady, let web {
                    web.createTab(id: tab.jsID, text: text)
                    web.activateTab(id: tab.jsID)
                }
            }

            refreshWindowTitle()
        } catch {
            Self.presentError("Could not open “\(url.lastPathComponent)”", error)
        }
    }

    /// Called by the web layer whenever a tab's editor text changes.
    func markDirty(tabID: String) {
        guard let uuid = UUID(uuidString: tabID),
              let index = tabs.firstIndex(where: { $0.id == uuid }) else { return }
        if !tabs[index].isDirty {
            tabs[index].isDirty = true
            refreshWindowTitle()
        }
    }

    /// Marks the visible tab dirty (used by the regression harness).
    func markDirty() {
        markDirty(tabID: selectedTabID.uuidString)
    }

    /// The single place the window title is assembled.
    private func refreshWindowTitle() {
        let name = selectedTab?.fileURL?.lastPathComponent
        let base = name.map { "MDacViewer — \($0)" } ?? "MDacViewer"
        let dirty = selectedTab?.isDirty ?? false
        windowTitle = dirty ? base + " *" : base
    }

    // MARK: - Save

    func saveDocument() {
        saveDocument(completion: nil)
    }

    func saveDocument(completion: ((Bool) -> Void)?) {
        saveDocument(tabID: selectedTabID, completion: completion)
    }

    /// Saves one tab: straight back to its file, or through the Save panel
    /// when the tab has no file yet. The completion reports whether the save
    /// actually happened (false when cancelled or failed).
    func saveDocument(tabID: UUID, completion: ((Bool) -> Void)?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            completion?(false)
            return
        }

        let finish: (String) -> Void = { [weak self] text in
            guard let self else { completion?(false); return }
            guard let index = self.tabs.firstIndex(where: { $0.id == tabID }) else {
                completion?(false)
                return
            }
            if let url = self.tabs[index].fileURL {
                let saved = self.write(text, to: url)
                if saved {
                    self.tabs[index].isDirty = false
                    self.refreshWindowTitle()
                }
                completion?(saved)
            } else {
                self.saveDocumentAs(tabID: tabID, text: text, completion: completion)
            }
        }

        if let web, web.isReady {
            web.getText(tabID: tab.jsID, completion: finish)
        } else {
            finish(tab.pendingText ?? "")
        }
    }

    func saveDocumentAs() {
        saveDocumentAs(tabID: selectedTabID, completion: nil)
    }

    private func saveDocumentAs(tabID: UUID,
                                completion: ((Bool) -> Void)?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            completion?(false)
            return
        }
        if let web, web.isReady {
            web.getText(tabID: tab.jsID) { [weak self] text in
                self?.saveDocumentAs(tabID: tabID, text: text, completion: completion)
            }
        } else {
            saveDocumentAs(tabID: tabID, text: tab.pendingText ?? "", completion: completion)
        }
    }

    private func saveDocumentAs(tabID: UUID,
                                text: String,
                                completion: ((Bool) -> Void)? = nil) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            completion?(false)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.nameFieldStringValue = tab.fileURL?.lastPathComponent ?? "Untitled.md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {
                completion?(false)
                return
            }
            guard let index = self.tabs.firstIndex(where: { $0.id == tabID }) else {
                completion?(false)
                return
            }
            let saved = self.write(text, to: url)
            if saved {
                self.tabs[index].fileURL = url
                self.tabs[index].isDirty = false
                self.refreshWindowTitle()
            }
            completion?(saved)
        }
    }

    @discardableResult
    private func write(_ text: String, to url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Self.presentError("Could not save “\(url.lastPathComponent)”", error)
            return false
        }
    }

    // MARK: - Unsaved-changes nudge

    /// Shows the standard Save / Cancel / Don't Save alert for one tab.
    private func promptSave(tabID: UUID,
                            window: NSWindow?,
                            completion: @escaping (Bool) -> Void) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            completion(true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(tab.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        alert.buttons[2].hasDestructiveAction = true

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.saveDocument(tabID: tabID) { saved in completion(saved) }
            case .alertThirdButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            // No window to hang the sheet on — run modally, but not before
            // applicationShouldTerminate has returned .terminateLater.
            DispatchQueue.main.async { handle(alert.runModal()) }
        }
    }

    /// Shows the save prompt for every dirty tab (window close or ⌘Q).
    /// `completion(true)` means it is safe to close or quit; `false` means the
    /// user cancelled or a save did not happen.
    func confirmClose(window: NSWindow?, completion: @escaping (Bool) -> Void) {
        if closeApproved || !isDirty {
            completion(true)
            return
        }
        // A nudge is already on screen (for example ⌘Q while the close sheet
        // is up) — let the pending one decide.
        if isNudging {
            completion(false)
            return
        }
        isNudging = true

        var remaining = tabs.filter { $0.isDirty }.map { $0.id }

        func finish(_ proceed: Bool) {
            isNudging = false
            if proceed { closeApproved = true }
            completion(proceed)
        }

        func promptNext() {
            guard let id = remaining.first else {
                finish(true)
                return
            }
            remaining.removeFirst()

            // The tab may already be clean (saved in an earlier step) or gone.
            guard let tab = tabs.first(where: { $0.id == id }), tab.isDirty else {
                promptNext()
                return
            }

            promptSave(tabID: id, window: window) { proceed in
                if proceed {
                    promptNext()
                } else {
                    finish(false)
                }
            }
        }

        promptNext()
    }

    // MARK: - Clipboard / reset / repo

    func copyAll() {
        guard let tab = selectedTab else { return }
        if let web, web.isReady {
            web.getText(tabID: tab.jsID) { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    func requestReset() {
        showResetConfirm = true
    }

    func performReset() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        // The editor text is not persisted anywhere, so resetting simply means
        // forgetting the current tab's file and emptying its editor model.
        tabs[index].fileURL = nil
        tabs[index].isDirty = false
        if let web, web.isReady {
            web.setText("", tabID: tabs[index].jsID)
        } else {
            tabs[index].pendingText = ""
        }
        refreshWindowTitle()
    }

    func openRepo() {
        if let url = URL(string: "https://github.com/SrHayward/MDacViewer") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    static let markdownTypes: [UTType] = {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        types.append(.plainText)
        return types
    }()

    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let string = String(data: data, encoding: .utf8) { return string }
        if let string = String(data: data, encoding: .isoLatin1) { return string }
        return String(decoding: data, as: UTF8.self)
    }

    static func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

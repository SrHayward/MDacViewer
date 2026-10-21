import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// App-wide state, bridged between the native toolbar/menus and the web editor.
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let darkModeKey = "darkMode"

    @Published var darkMode = false
    @Published var syncScroll = false
    @Published var windowTitle = "MDacViewer"
    @Published var showResetConfirm = false

    /// True while the editor holds edits that have not been saved. This covers
    /// untitled text typed in a fresh session too, which is shown as
    /// "MDacViewer *" — unsaved text must never be discarded silently, so the
    /// close/quit nudge applies to it as well.
    @Published private(set) var isDirty = false {
        didSet { if isDirty != oldValue { refreshWindowTitle() } }
    }

    /// Set once the user has approved closing (Save or Don't Save), so the
    /// window-close and app-quit paths do not ask a second time.
    private(set) var closeApproved = false
    private var isNudging = false

    weak var web: WebController?

    private(set) var currentFileURL: URL?
    /// Text queued while the web layer has not finished booting (e.g. file opened via Finder at launch).
    var pendingInitialText: String?

    private init() {
        darkMode = UserDefaults.standard.bool(forKey: Self.darkModeKey)
        applyAppearance()
    }

    // MARK: - Settings

    /// Push the current toggle states into the web layer (idempotent) and
    /// apply the app-wide appearance so the window chrome matches too.
    func pushSettingsToWeb() {
        web?.setTheme(dark: darkMode)
        web?.setSyncScroll(enabled: syncScroll)
        UserDefaults.standard.set(darkMode, forKey: Self.darkModeKey)
        applyAppearance()
    }

    /// Switches the entire app — title bar, toolbar, menus and panes — between
    /// light and dark, following the in-app Dark mode toggle.
    func applyAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
    }

    /// Called by the web layer once it has booted, reporting its persisted settings.
    func webReady(dark: Bool, sync: Bool) {
        darkMode = dark
        syncScroll = sync
        if let text = pendingInitialText {
            pendingInitialText = nil
            web?.setText(text)
        }
        pushSettingsToWeb()
    }

    // MARK: - Open

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.markdownTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url: url)
        }
    }

    func open(url: URL) {
        do {
            let text = try Self.readText(at: url)
            currentFileURL = url
            isDirty = false
            refreshWindowTitle()
            if let web {
                web.setText(text)
            } else {
                pendingInitialText = text
            }
        } catch {
            Self.presentError("Could not open “\(url.lastPathComponent)”", error)
        }
    }

    /// Called by the web layer whenever the editor text changes. Untitled text
    /// counts as dirty too, so typing in a fresh session shows the asterisk and
    /// closing prompts instead of discarding the text.
    func markDirty() {
        if !isDirty { isDirty = true }
    }

    /// The single place the window title is assembled.
    private func refreshWindowTitle() {
        let base = currentFileURL.map { "MDacViewer — \($0.lastPathComponent)" } ?? "MDacViewer"
        windowTitle = isDirty ? base + " *" : base
    }

    // MARK: - Save

    func saveDocument() {
        saveDocument(completion: nil)
    }

    /// Saves the editor text: straight back to the open file, or through the
    /// Save panel when there is no file yet. The completion reports whether
    /// the save actually happened (false when cancelled or failed).
    func saveDocument(completion: ((Bool) -> Void)?) {
        guard let web else { completion?(false); return }
        web.getText { [weak self] text in
            guard let self else { completion?(false); return }
            if let url = self.currentFileURL {
                let saved = self.write(text, to: url)
                if saved { self.isDirty = false }
                completion?(saved)
            } else {
                self.saveDocumentAs(with: text, completion: completion)
            }
        }
    }

    func saveDocumentAs() {
        guard let web else { return }
        web.getText { [weak self] text in
            self?.saveDocumentAs(with: text)
        }
    }

    private func saveDocumentAs(with text: String, completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            guard let self else { completion?(false); return }
            let saved = self.write(text, to: url)
            if saved {
                self.currentFileURL = url
                self.isDirty = false
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

    /// Shows the standard Save / Cancel / Don't Save alert when there are
    /// unsaved edits (an open file, or untitled text). `completion(true)` means
    /// it is safe to close or quit (saved, or explicitly discarded); `false`
    /// means the user cancelled or the save did not happen.
    func confirmClose(window: NSWindow?, completion: @escaping (Bool) -> Void) {
        if !isDirty || closeApproved {
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

        let finish: (Bool) -> Void = { [weak self] proceed in
            guard let self else { return }
            self.isNudging = false
            if proceed { self.closeApproved = true }
            completion(proceed)
        }

        let alert = NSAlert()
        let name = currentFileURL?.lastPathComponent ?? "Untitled"
        alert.messageText = "Do you want to save the changes you made to “\(name)”?"
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
                self.saveDocument { saved in finish(saved) }
            case .alertThirdButtonReturn:
                finish(true)
            default:
                finish(false)
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

    // MARK: - Clipboard / reset / repo

    func copyAll() {
        guard let web else { return }
        web.getText { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    func requestReset() {
        showResetConfirm = true
    }

    func performReset() {
        // The editor text is not persisted anywhere, so resetting simply means
        // forgetting the current file and asking the web layer to empty the editor.
        currentFileURL = nil
        isDirty = false
        refreshWindowTitle()
        web?.reset()
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

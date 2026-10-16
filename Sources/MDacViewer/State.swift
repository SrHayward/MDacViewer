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
            windowTitle = "MDacViewer — \(url.lastPathComponent)"
            if let web {
                web.setText(text)
            } else {
                pendingInitialText = text
            }
        } catch {
            Self.presentError("Could not open “\(url.lastPathComponent)”", error)
        }
    }

    // MARK: - Save

    func saveDocument() {
        guard let web else { return }
        web.getText { [weak self] text in
            guard let self else { return }
            if let url = self.currentFileURL {
                self.write(text, to: url)
            } else {
                self.saveDocumentAs(with: text)
            }
        }
    }

    func saveDocumentAs() {
        guard let web else { return }
        web.getText { [weak self] text in
            self?.saveDocumentAs(with: text)
        }
    }

    private func saveDocumentAs(with text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.write(text, to: url)
            self?.currentFileURL = url
            self?.windowTitle = "MDacViewer — \(url.lastPathComponent)"
        }
    }

    private func write(_ text: String, to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Self.presentError("Could not save “\(url.lastPathComponent)”", error)
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
        currentFileURL = nil
        windowTitle = "MDacViewer"
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

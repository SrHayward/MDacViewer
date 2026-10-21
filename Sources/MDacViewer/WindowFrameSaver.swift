import SwiftUI
import AppKit

/// Sets a comfortable window size on first launch and remembers the
/// window's size/position between launches.
struct WindowFrameSaver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        var attempts = 0

        func tryAttach() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempts == 0 ? 0 : 0.2)) {
                if let window = view.window {
                    context.coordinator.attach(to: window)
                    return
                }
                attempts += 1
                if attempts < 10 { tryAttach() }
            }
        }
        tryAttach()

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        private static let frameKey = "mainWindowFrame"
        private var tokens: [NSObjectProtocol] = []
        private var saveWorkItem: DispatchWorkItem?
        private weak var window: NSWindow?

        func attach(to window: NSWindow) {
            self.window = window
            interceptCloseButton(window)
            restore(window)

            let center = NotificationCenter.default
            let resize = center.addObserver(forName: NSWindow.didResizeNotification,
                                           object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.scheduleSave(window)
            }
            let move = center.addObserver(forName: NSWindow.didMoveNotification,
                                          object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.scheduleSave(window)
            }
            tokens = [resize, move]
        }

        // MARK: - Unsaved-changes nudge
        //
        // SwiftUI owns the window's delegate and relies on it for the scene
        // lifecycle — replacing it makes the window close itself on the next
        // scene update (for example when a file is opened). The red close
        // button is intercepted instead; quitting (⌘Q) is covered by
        // applicationShouldTerminate.

        private func interceptCloseButton(_ window: NSWindow) {
            guard let button = window.standardWindowButton(.closeButton) else { return }
            button.target = self
            button.action = #selector(closeButtonPressed)
        }

        @objc private func closeButtonPressed() {
            guard let window else { return }
            let app = AppState.shared
            guard app.isDirty && !app.closeApproved else {
                window.performClose(nil)
                return
            }
            app.confirmClose(window: window) { proceed in
                guard proceed else { return }
                window.close()
            }
        }

        // MARK: - Persistence

        private func scheduleSave(_ window: NSWindow) {
            saveWorkItem?.cancel()
            let item = DispatchWorkItem { [weak window] in
                guard let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame),
                                          forKey: Self.frameKey)
            }
            saveWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }

        private func restore(_ window: NSWindow) {
            if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
                let frame = NSRectFromString(saved)
                let visible = frame.width >= 400 && frame.height >= 300
                    && NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
                if visible {
                    window.setFrame(frame, display: true)
                    return
                }
            }
            // First run: comfortable default, centred.
            window.setContentSize(NSSize(width: 1240, height: 780))
            window.center()
        }
    }
}

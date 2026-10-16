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

    final class Coordinator {
        private static let frameKey = "mainWindowFrame"
        private var tokens: [NSObjectProtocol] = []
        private var saveWorkItem: DispatchWorkItem?

        func attach(to window: NSWindow) {
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

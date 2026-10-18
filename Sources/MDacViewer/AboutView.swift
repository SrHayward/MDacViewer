import SwiftUI
import AppKit

/// The About window: current version, a manual update check, and the shared
/// update state from ``UpdateChecker``.
struct AboutView: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("MDacViewer")
                .font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                Text("Version \(updates.currentVersion)")
                    .foregroundStyle(.secondary)
                action
            }

            status
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 16)

            Text(copyright)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 320)
    }

    /// The button is contextual: check on demand, then offer the download
    /// once an update is known.
    @ViewBuilder
    private var action: some View {
        if updates.isChecking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
            }
        } else if updates.updateAvailable {
            Button("Download Update…") { updates.openReleasesPage() }
        } else {
            Button("Check for Updates") { updates.check(manual: true) }
        }
    }

    @ViewBuilder
    private var status: some View {
        if updates.lastManualCheckFailed {
            Text("Couldn't check for updates. Please try again later.")
        } else if updates.updateAvailable, let latest = updates.latestVersion {
            Text("Version \(latest) is available.")
        } else if updates.lastChecked != nil {
            Text("You're up to date.")
        } else {
            Text(" ")
        }
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Henry Hayward. Licensed under the Apache License 2.0."
    }
}

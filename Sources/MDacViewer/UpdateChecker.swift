import Foundation
import SwiftUI
import AppKit

/// Checks GitHub Releases for a newer version of MDacViewer.
///
/// Deliberately minimal, per the feature request:
/// - one GET to the public releases API, reading `tag_name`;
/// - numeric, component-by-component version comparison;
/// - the result persists across launches and automatic checks run at most
///   once a day;
/// - no auto-download, no auto-install, no third-party framework.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// The repo's "latest release" page — always resolves to the newest
    /// release, so it never needs to be built from the API response.
    static let releasesPageURL = URL(string: "https://github.com/SrHayward/MDacViewer/releases/latest")!

    private static let defaultFeedURL = URL(string: "https://api.github.com/repos/SrHayward/MDacViewer/releases/latest")!

    /// Automatic checks happen at most this often.
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// First check after launch — late enough that it never delays startup.
    private static let launchDelay: TimeInterval = 5
    /// How often the app re-evaluates whether a check is due while it stays open.
    private static let timerTick: TimeInterval = 60 * 60

    private static let latestVersionKey = "updates.latestVersion"
    private static let lastCheckedKey = "updates.lastChecked"
    /// Test hook: overrides the API feed (see Scripts/test-update-check.sh).
    private static let feedURLOverrideKey = "updates.feedURL"

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    /// True when the latest known release is newer than the running build.
    /// Derived from persisted state, so the toolbar indicator survives
    /// relaunches (and clears itself once the user updates the app).
    @Published private(set) var updateAvailable = false
    /// Tag name of the latest known release, e.g. "1.0.1".
    @Published private(set) var latestVersion: String?
    @Published private(set) var isChecking = false
    /// Timestamp of the last successful check (persisted).
    @Published private(set) var lastChecked: Date?
    /// Set when a *manual* check fails, so the About window can report it;
    /// automatic failures stay silent.
    @Published private(set) var lastManualCheckFailed = false

    /// The installed version, straight from the app bundle's Info.plist.
    /// Unbundled development builds have no Info.plist and fall back to 0.0.0.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private init() {
        if let tag = defaults.string(forKey: Self.latestVersionKey) {
            latestVersion = tag
            updateAvailable = Self.isNewer(tag, than: currentVersion)
        }
        let checked = defaults.double(forKey: Self.lastCheckedKey)
        if checked > 0 { lastChecked = Date(timeIntervalSince1970: checked) }
    }

    // MARK: - Scheduling

    /// Called once at launch: schedules the delayed first check and the
    /// periodic due-check that keeps long-running sessions covered.
    func start() {
        guard timer == nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.launchDelay * 1_000_000_000))
            await MainActor.run { self.checkIfDue() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.timerTick, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    /// Runs a check only when 24 h have passed since the last successful one.
    private func checkIfDue() {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        check()
    }

    // MARK: - Checking

    func check(manual: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        if manual { lastManualCheckFailed = false }
        let runningVersion = currentVersion

        Task {
            do {
                let tag = try await Self.fetchLatestTag()
                await MainActor.run {
                    self.recordSuccessfulCheck(tag: tag, runningVersion: runningVersion)
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                    if manual { self.lastManualCheckFailed = true }
                }
            }
        }
    }

    private func recordSuccessfulCheck(tag: String?, runningVersion: String) {
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastCheckedKey)
        lastChecked = now
        isChecking = false
        if let tag {
            defaults.set(tag, forKey: Self.latestVersionKey)
            latestVersion = tag
            updateAvailable = Self.isNewer(tag, than: runningVersion)
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
    }

    // MARK: - Networking

    /// GETs the feed and returns the release's tag name.
    /// Returns `nil` for HTTP 404 (no releases yet). Throws on anything else.
    static func fetchLatestTag(from override: URL? = nil) async throws -> String? {
        var request = URLRequest(url: override ?? Self.feedURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("MDacViewer/\(Self.installedVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        return try JSONDecoder().decode(Release.self, from: data).tagName
    }

    /// The feed to use: a test override, or the real API.
    private static var feedURL: URL {
        if let override = UserDefaults.standard.string(forKey: feedURLOverrideKey),
           let url = URL(string: override) {
            return url
        }
        if let override = ProcessInfo.processInfo.environment["MDACVIEWER_UPDATE_FEED"],
           let url = URL(string: override) {
            return url
        }
        return defaultFeedURL
    }

    /// Version from the bundle; "0.0.0" when running unbundled (dev builds).
    private static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - Version comparison

    /// True when `remote` is a numerically newer version than `local`.
    ///
    /// Components are compared as integers, left to right; missing trailing
    /// components count as zero; a leading "v" is ignored. This avoids the
    /// classic string-compare bug where "1.0.10" sorts before "1.0.9".
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = components(of: remote)
        let localParts = components(of: local)
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        return trimmed
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
}

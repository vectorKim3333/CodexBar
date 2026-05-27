import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var latestVersion: String?
    private(set) var lastCheckedAt: Date?
    private(set) var lastErrorDescription: String?

    private static let versionURL = URL(
        string: "https://raw.githubusercontent.com/vectorKim3333/CodexBar/main/version.env")!
    private static let checkInterval: TimeInterval = 3600  // 1 hour
    private static let installGuideURL = URL(
        string: "https://madup.atlassian.net/wiki/spaces/CT/blog/4864671781/ClCoBar+macOS+Claude+Codex")!

    private var pollingTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard self.pollingTask == nil else { return }
        self.pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    func stop() {
        self.pollingTask?.cancel()
        self.pollingTask = nil
    }

    /// Manual one-shot check. Safe to call repeatedly.
    func check() async {
        do {
            var req = URLRequest(url: Self.versionURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.lastErrorDescription = "HTTP \(http.statusCode)"
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                self.lastErrorDescription = "decode failed"
                return
            }
            for line in text.split(separator: "\n") {
                if line.hasPrefix("MARKETING_VERSION=") {
                    let version = String(line.dropFirst("MARKETING_VERSION=".count))
                        .trimmingCharacters(in: .whitespaces)
                    self.latestVersion = version
                    self.lastCheckedAt = Date()
                    self.lastErrorDescription = nil
                    return
                }
            }
            self.lastErrorDescription = "MARKETING_VERSION not found"
        } catch {
            self.lastErrorDescription = error.localizedDescription
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var hasUpdate: Bool {
        guard let latest = self.latestVersion else { return false }
        return Self.compareVersions(self.currentVersion, latest) == .orderedAscending
    }

    /// Action invoked from menu rows.
    @objc func openInstallGuide() {
        NSWorkspace.shared.open(Self.installGuideURL)
    }

    private static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }
}

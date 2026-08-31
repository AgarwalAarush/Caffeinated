import AppKit
import Combine
import Foundation

/// Checks GitHub Releases and replaces this .app in place.
/// Sparkle is the usual Mac path, but it wants a Developer ID; CI builds are ad-hoc.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var status: String = ""
    @Published var isBusy = false
    @Published var availableVersion: String?

    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: PrefKey.autoCheck) }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private let repo = "AgarwalAarush/Caffeinated"
    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: PrefKey.lastCheck) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.lastCheck) }
    }

    private init() {
        autoCheck = UserDefaults.standard.object(forKey: PrefKey.autoCheck) as? Bool ?? true
    }

    func checkIfDue() {
        guard autoCheck, !isBusy else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 60 * 60 * 12 { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        if interactive { status = "Checking…" }
        defer { isBusy = false }

        do {
            let release = try await fetchLatest()
            lastCheck = Date()
            let latest = Self.normalize(release.tag_name)
            if Self.isNewer(latest, than: currentVersion) {
                availableVersion = latest
                status = "\(latest) is available"
            } else {
                availableVersion = nil
                if interactive { status = "You’re on \(currentVersion)" }
                else { status = "" }
            }
        } catch UpdateError.noReleases {
            availableVersion = nil
            if interactive { status = "No releases yet" }
        } catch {
            availableVersion = nil
            if interactive { status = "Couldn’t check for updates" }
        }
    }

    func install() async {
        guard !isBusy else { return }
        isBusy = true
        status = "Downloading…"
        defer { isBusy = false }

        do {
            let release = try await fetchLatest()
            guard let asset = pickZip(release.assets) else {
                status = "Release has no zip"
                return
            }
            let zip = try await download(asset.browser_download_url)
            status = "Installing…"
            let newApp = try unzipApp(from: zip)
            try relaunch(replacing: Bundle.main.bundleURL, with: newApp)
        } catch let error as UpdateError {
            status = error.userMessage
        } catch {
            status = "Update failed"
        }
    }

    private func pickZip(_ assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        assets.first { $0.name == "Caffeinated.zip" }
            ?? assets.first { $0.name.hasSuffix(".zip") }
    }

    private func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("Caffeinated/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw UpdateError.noReleases }
            if http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(_ url: URL) async throws -> URL {
        let (temp, _) = try await URLSession.shared.download(from: url)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Caffeinated-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    private func unzipApp(from zip: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Caffeinated-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zip.path, dest.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        let direct = dest.appendingPathComponent("Caffeinated.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let found = FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "Caffeinated.app" && $0.pathExtension == "app" }) {
            return found
        }
        throw UpdateError.unzipFailed
    }

    private func relaunch(replacing app: URL, with newApp: URL) throws {
        let parent = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        set -euo pipefail
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(Self.shQuote(app.path))
        /usr/bin/ditto \(Self.shQuote(newApp.path)) \(Self.shQuote(app.path))
        /usr/bin/xattr -cr \(Self.shQuote(app.path)) || true
        /usr/bin/open \(Self.shQuote(app.path))
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinated-relaunch.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        NSApp.terminate(nil)
    }

    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let n = max(l.count, c.count)
        for i in 0..<n {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }

    private static func shQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum PrefKey {
        static let autoCheck = "autoCheckUpdates"
        static let lastCheck = "lastUpdateCheck"
    }

    private enum UpdateError: Error {
        case noReleases, unzipFailed, notWritable, http(Int)

        var userMessage: String {
            switch self {
            case .noReleases: return "No releases yet"
            case .unzipFailed: return "Couldn’t unpack update"
            case .notWritable: return "Move the app to Applications, then retry"
            case .http: return "Couldn’t download update"
            }
        }
    }
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }
}

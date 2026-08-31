import AppKit
import Combine
import Foundation

/// Checks GitHub Releases and replaces this .app in place.
/// Sparkle is the usual Mac path, but it wants a Developer ID; CI builds are ad-hoc.
///
/// The GitHub repo must be **public**. Private repos 404 both `releases/latest`
/// and the zip URL for an unauthenticated `URLSession` (the app has no token).
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
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(_ url: URL) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
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
        let found: URL
        if FileManager.default.fileExists(atPath: direct.path) {
            found = direct
        } else if let match = FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "Caffeinated.app" && $0.pathExtension == "app" }) {
            found = match
        } else {
            throw UpdateError.unzipFailed
        }

        let exe = found.appendingPathComponent("Contents/MacOS/Caffeinated")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw UpdateError.unzipFailed
        }
        return found
    }

    private func relaunch(replacing app: URL, with newApp: URL) throws {
        if app.path.contains("/AppTranslocation/") {
            throw UpdateError.notWritable
        }
        try assertParentWritable(app.deletingLastPathComponent())

        let pid = ProcessInfo.processInfo.processIdentifier
        let quotedApp = Self.shQuote(app.path)
        let quotedNew = Self.shQuote(newApp.path)
        let quotedBackup = Self.shQuote(app.path + ".caffeinated-old")
        let script = """
        #!/bin/bash
        trap '' HUP
        set -euo pipefail
        APP=\(quotedApp)
        NEW=\(quotedNew)
        BACKUP=\(quotedBackup)
        LOG="${HOME}/Library/Logs/Caffeinated-update.log"
        mkdir -p "$(dirname "$LOG")"
        exec >>"$LOG" 2>&1
        echo "$(date) waiting for pid \(pid)"
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.4
        rm -rf "$BACKUP"
        if [ -e "$APP" ]; then
          mv "$APP" "$BACKUP"
        fi
        if ! /usr/bin/ditto "$NEW" "$APP"; then
          echo "ditto failed; restoring backup"
          rm -rf "$APP"
          if [ -e "$BACKUP" ]; then mv "$BACKUP" "$APP"; fi
          exit 1
        fi
        rm -rf "$BACKUP"
        /usr/bin/xattr -cr "$APP" || true
        echo "$(date) launching"
        /usr/bin/open "$APP"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinated-relaunch.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try launchDetached(scriptURL)
        NSApp.terminate(nil)
    }

    /// Start the helper in the background and wait for the launcher to exit so
    /// `Process` deinit / app quit cannot take the updater with it.
    private func launchDetached(_ scriptURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [
            "-c",
            "trap '' HUP; /usr/bin/nohup \(Self.shQuote(scriptURL.path)) >/dev/null 2>&1 &"
        ]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw UpdateError.relaunchFailed }
    }

    private func assertParentWritable(_ parent: URL) throws {
        let probe = parent.appendingPathComponent(".caffeinated-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw UpdateError.notWritable
        }
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
        case unzipFailed, notWritable, http(Int), relaunchFailed

        var userMessage: String {
            switch self {
            case .unzipFailed: return "Couldn’t unpack update"
            case .notWritable: return "Move the app to Applications, then retry"
            case .http: return "Couldn’t download update"
            case .relaunchFailed: return "Couldn’t start installer"
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

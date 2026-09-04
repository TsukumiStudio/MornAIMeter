import AppKit
import Foundation

/// GitHub Releases の最新タグと現在バージョンを比較し、必要なら更新を実行する。
final class Updater: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case available(tag: String, url: String)
        case failed(String)
    }

    @Published var state: State = .idle

    private static let brewCandidatePaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// v プレフィックスを除き "." 区切りの各要素を Int にして辞書順比較する。パースできなければ false。
    static func isNewer(latestTag: String, current: String) -> Bool {
        guard let latest = parseVersion(latestTag), let current = parseVersion(current) else {
            return false
        }
        let count = max(latest.count, current.count)
        for i in 0..<count {
            let l = i < latest.count ? latest[i] : 0
            let c = i < current.count ? current[i] : 0
            if l != c { return l > c }
        }
        return false
    }

    private static func parseVersion(_ raw: String) -> [Int]? {
        var s = raw
        if s.hasPrefix("v") { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var result: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func findBrewPath() -> String? {
        for path in brewCandidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private var isInstalledViaBrew: Bool {
        Bundle.main.bundlePath == "/Applications/MornAIMeter.app" && Self.findBrewPath() != nil
    }

    var updateButtonTitle: String {
        isInstalledViaBrew ? "更新する" : "Release ページを開く"
    }

    func check() {
        state = .checking
        Task { @MainActor in
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/matsufriends/MornAIMeter/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("MornAIMeter", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    state = .failed("確認できませんでした")
                    return
                }
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tag = json["tag_name"] as? String,
                    let htmlUrl = json["html_url"] as? String
                else {
                    state = .failed("確認できませんでした")
                    return
                }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                if Self.isNewer(latestTag: tag, current: current) {
                    state = .available(tag: tag, url: htmlUrl)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed("確認できませんでした")
            }
        }
    }

    func performUpdate(releaseURL: String) {
        guard isInstalledViaBrew, let brewPath = Self.findBrewPath() else {
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MornAIMeter")
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logPath = logDirectory.appendingPathComponent("update.log").path
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let logHandle = FileHandle(forWritingAtPath: logPath) else { return }
        logHandle.seekToEndOfFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(brewPath) update && \(brewPath) upgrade --cask mornaimeter && open -a MornAIMeter"]
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApp.terminate(nil)
        }
    }
}

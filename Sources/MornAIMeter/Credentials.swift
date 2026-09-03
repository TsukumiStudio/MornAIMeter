import Foundation

/// refresh は行わない。CLI 側 (claude / codex) が定期的に更新した Keychain / auth.json を
/// 読むだけの用途。トークン更新の処理・書き込みは意図的に実装しない
/// (Codex 側の更新用トークンは使い捨てローテーションで CLI 側と競合するため。README「注意」節参照)。
///
/// Keychain の読み取りは Security フレームワークの API を直接呼ぶのではなく、
/// /usr/bin/security コマンドを Process 経由で呼ぶ。ad-hoc 署名のアプリはビルドごとに
/// cdhash が変わり、Security API を直に叩くと macOS の Keychain ACL が『常に許可』を
/// 覚えてくれない (再ビルドのたびに許可ダイアログが出る) が、Apple 署名の /usr/bin/security
/// を経由すると許可対象が security コマンドになり、ダイアログは初回のみになる。
enum CredentialError: Error, LocalizedError {
    case keychainNotFound
    case fileNotFound
    case invalidJSON
    case expired

    var errorDescription: String? {
        switch self {
        case .keychainNotFound:
            return "Claude Code にログインしていないか、Keychain へのアクセスが拒否されました (claude login)"
        case .fileNotFound:
            return "~/.codex/auth.json が見つかりません (codex login)"
        case .invalidJSON:
            return "資格情報の JSON 解析に失敗しました"
        case .expired:
            return "Antigravity のトークンが期限切れ。agy を起動すると更新されます"
        }
    }
}

enum Credentials {
    private static let cacheTTL: TimeInterval = 60 * 60
    private static var cachedToken: (token: String, fetchedAt: Date)?
    private static var cachedAntigravityToken: (token: String, expiry: Date)?
    private static var lastAgyRefreshAt: Date?

    /// security find-generic-password の標準出力 (末尾改行あり) から accessToken を取り出す純粋関数。
    static func parseClaudeAccessToken(fromSecurityOutput output: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .newlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw CredentialError.invalidJSON
        }
        return token
    }

    /// forceRefresh: false でもキャッシュが無い/1時間超なら読み直す。401 応答時は呼び出し側が true で呼ぶ。
    static func claudeAccessToken(forceRefresh: Bool = false) throws -> String {
        if !forceRefresh,
           let cached = cachedToken,
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.token
        }
        let output = try runSecurityFindGenericPassword(service: "Claude Code-credentials")
        let token = try parseClaudeAccessToken(fromSecurityOutput: output)
        cachedToken = (token, Date())
        return token
    }

    private static func runSecurityFindGenericPassword(service: String, account: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        arguments.append("-w")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw CredentialError.keychainNotFound
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else {
            throw CredentialError.keychainNotFound
        }
        return output
    }

    static func codexTokens() throws -> (accessToken: String, accountId: String) {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CredentialError.fileNotFound
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let accountId = tokens["account_id"] as? String else {
            throw CredentialError.invalidJSON
        }
        return (accessToken, accountId)
    }

    /// ISO8601 文字列をパースする純粋関数 (単体テスト対象)。小数秒ありを先に試し、無ければ整数秒側にフォールバックする。
    static func parseExpiry(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: value) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// gemini/antigravity の Keychain 項目 (go-keyring-base64: プレフィックス + base64 の JSON、
    /// またはプレフィックス無しの生 JSON) から accessToken と expiry を取り出す純粋関数。
    static func parseAntigravityKeychainValue(_ raw: String) throws -> (accessToken: String, expiry: Date?) {
        let trimmed = raw.trimmingCharacters(in: .newlines)
        let prefix = "go-keyring-base64:"
        let jsonString: String
        if trimmed.hasPrefix(prefix) {
            let base64Part = String(trimmed.dropFirst(prefix.count))
            guard let decoded = Data(base64Encoded: base64Part),
                  let decodedString = String(data: decoded, encoding: .utf8) else {
                throw CredentialError.invalidJSON
            }
            jsonString = decodedString
        } else {
            jsonString = trimmed
        }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? [String: Any],
              let accessToken = token["access_token"] as? String else {
            throw CredentialError.invalidJSON
        }
        let expiry = (token["expiry"] as? String).flatMap { parseExpiry($0) }
        return (accessToken, expiry)
    }

    private static func readAntigravityKeychain() throws -> (accessToken: String, expiry: Date?) {
        let raw = try runSecurityFindGenericPassword(service: "gemini", account: "antigravity")
        return try parseAntigravityKeychainValue(raw)
    }

    /// gemini/antigravity の Keychain 項目を読む。期限切れ (60 秒未満を含む) のときは
    /// agy -p ping を裏起動して Keychain を更新させてから 1 回だけ読み直す。
    static func antigravityAccessToken(now: Date = Date()) throws -> String {
        let notExpiringSoon: (Date?) -> Bool = { expiry in
            guard let expiry else { return false }
            return expiry.timeIntervalSince(now) >= 60
        }
        if let cached = cachedAntigravityToken, notExpiringSoon(cached.expiry) {
            return cached.token
        }
        let first = try readAntigravityKeychain()
        if notExpiringSoon(first.expiry), let expiry = first.expiry {
            cachedAntigravityToken = (first.accessToken, expiry)
            return first.accessToken
        }
        refreshAntigravityTokenViaAgy()
        let second = try readAntigravityKeychain()
        guard notExpiringSoon(second.expiry), let expiry = second.expiry else {
            throw CredentialError.expired
        }
        cachedAntigravityToken = (second.accessToken, expiry)
        return second.accessToken
    }

    /// agy -p ping を stdin なしで裏起動し、Keychain のトークンを更新させる。
    /// 見つからない/直近5分以内に実行済みなら何もしない。最大20秒待って諦める。
    private static func refreshAntigravityTokenViaAgy() {
        let now = Date()
        if let last = lastAgyRefreshAt, now.timeIntervalSince(last) < 300 {
            return
        }
        guard let agyPath = findAgyExecutable() else { return }
        lastAgyRefreshAt = now

        let process = Process()
        process.executableURL = URL(fileURLWithPath: agyPath)
        process.arguments = ["-p", "ping"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            process.terminate()
        }
    }

    private static func findAgyExecutable() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

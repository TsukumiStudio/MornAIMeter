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
        let output = try runSecurityFindGenericPassword()
        let token = try parseClaudeAccessToken(fromSecurityOutput: output)
        cachedToken = (token, Date())
        return token
    }

    private static func runSecurityFindGenericPassword() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
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

    /// ~/.gemini/jetski-standalone-oauth-token を読む。refresh は行わない (client_secret を保持しないため)。
    static func antigravityAccessToken(now: Date = Date()) throws -> String {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CredentialError.fileNotFound
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? [String: Any],
              let accessToken = token["access_token"] as? String,
              let expiryString = token["expiry"] as? String,
              let expiry = parseExpiry(expiryString) else {
            throw CredentialError.invalidJSON
        }
        guard expiry > now else {
            throw CredentialError.expired
        }
        return accessToken
    }
}

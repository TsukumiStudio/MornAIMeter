import Foundation

enum ServiceUsageError: Error, LocalizedError {
    case needsLogin(String)
    case network(String, retryNotBefore: Date? = nil)

    var errorDescription: String? {
        switch self {
        case .needsLogin(let cmd):
            return "再ログインが必要 (\(cmd))"
        case .network(let message, _):
            return message
        }
    }
}

/// 429 応答の Retry-After ヘッダをパースする純粋関数 (単体テスト対象)。
/// 整数秒・HTTP-date (RFC 1123) のどちらでも来る。欠落・パース失敗時は既定 300 秒後。
enum RetryAfterParsing {
    static let defaultInterval: TimeInterval = 300

    static func parse(header: String?, now: Date) -> Date {
        guard let header, !header.isEmpty else {
            return now.addingTimeInterval(defaultInterval)
        }
        if let seconds = Double(header) {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) {
            return date
        }
        return now.addingTimeInterval(defaultInterval)
    }
}

enum UsageFetcher {
    static func fetchClaude() async -> Result<ClaudeUsage, ServiceUsageError> {
        do {
            let token = try Credentials.claudeAccessToken()
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            var (data, response) = try await URLSession.shared.data(for: request)
            guard var http = response as? HTTPURLResponse else {
                return .failure(.network("不明な応答"))
            }
            if http.statusCode == 401 {
                // キャッシュしたトークンが古い可能性があるので1回だけ読み直して再試行する
                let refreshedToken = try Credentials.claudeAccessToken(forceRefresh: true)
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await URLSession.shared.data(for: request)
                guard let refreshedHttp = response as? HTTPURLResponse else {
                    return .failure(.network("不明な応答"))
                }
                http = refreshedHttp
                if http.statusCode == 401 {
                    return .failure(.needsLogin("claude login"))
                }
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 {
                    let now = Date()
                    let retryNotBefore = RetryAfterParsing.parse(header: http.value(forHTTPHeaderField: "Retry-After"), now: now)
                    return .failure(.network("usage API 429", retryNotBefore: retryNotBefore))
                }
                return .failure(.network("usage API \(http.statusCode)"))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.network("応答の解析に失敗しました"))
            }
            return .success(UsageMapping.mapClaude(json))
        } catch is CredentialError {
            return .failure(.needsLogin("claude login"))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // Mac からは chatgpt.com に直接通る想定。403 (Bot Management 相当) のときだけ
    // android.chat.openai.com へフォールバックする (worker 版は Cloudflare の IP 帯が弾かれるための回避で、
    // Mac のローカル IP からは事情が異なる。README「Codex を chatgpt.com ではなく…」参照)。
    static func fetchCodex() async -> Result<CodexUsage, ServiceUsageError> {
        do {
            let tokens = try Credentials.codexTokens()
            let hosts = [
                "https://chatgpt.com/backend-api/wham/usage",
                "https://android.chat.openai.com/backend-api/wham/usage",
            ]
            var lastStatus = 0
            for host in hosts {
                var request = URLRequest(url: URL(string: host)!)
                request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(tokens.accountId, forHTTPHeaderField: "chatgpt-account-id")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                lastStatus = http.statusCode
                if http.statusCode == 401 {
                    return .failure(.needsLogin("codex login"))
                }
                if http.statusCode == 403 { continue }
                if http.statusCode == 429 {
                    let now = Date()
                    let retryNotBefore = RetryAfterParsing.parse(header: http.value(forHTTPHeaderField: "Retry-After"), now: now)
                    return .failure(.network("usage API 429", retryNotBefore: retryNotBefore))
                }
                guard http.statusCode == 200 else {
                    return .failure(.network("usage API \(http.statusCode)"))
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return .failure(.network("応答の解析に失敗しました"))
                }
                return .success(UsageMapping.mapWham(json))
            }
            return .failure(.network("usage API \(lastStatus)"))
        } catch is CredentialError {
            return .failure(.needsLogin("codex login"))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}

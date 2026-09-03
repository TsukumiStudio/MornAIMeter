import Foundation

struct WindowUsage: Equatable {
    let percent: Double
    let resetsAt: Date?
    let windowSeconds: Double
}

/// Claude の scoped 配列・Codex の additional 配列の先頭要素 (名前付きの枠)。
struct NamedWindow: Equatable {
    let name: String?
    let window: WindowUsage
}

struct ClaudeUsage: Equatable {
    var fiveHour: WindowUsage?
    var sevenDay: WindowUsage?
    /// scoped (weekly_scoped) 配列の先頭要素。モデル別週次枠。
    var scoped: NamedWindow?
}

struct CodexUsage: Equatable {
    var primary: WindowUsage?
    var secondary: WindowUsage?
    /// additional_rate_limits 配列の先頭要素 (Codex Spark)。
    var additional: NamedWindow?

    /// primary/secondary のどちらが5時間枠/週次枠かは window_seconds でしか判定できない
    /// (worker/src/index.js の mapWham 由来)。
    var fiveHour: WindowUsage? {
        [primary, secondary].compactMap { $0 }.first { !UsageMapping.isWeekly(windowSeconds: $0.windowSeconds) }
    }

    var weekly: WindowUsage? {
        [primary, secondary].compactMap { $0 }.first { UsageMapping.isWeekly(windowSeconds: $0.windowSeconds) }
    }
}

/// メニューバーに表示する枠の選択肢。UserDefaults ("menuBarGauge") に保存する。
enum MenuBarGaugeSelection: String, CaseIterable, Identifiable {
    case claude5h
    case claudeWeekly
    case claudeScoped
    case codexWeekly
    case codexAdditional

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude5h: return "Claude 5時間枠"
        case .claudeWeekly: return "Claude 週次枠"
        case .claudeScoped: return "Claude 週次 (モデル別)"
        case .codexWeekly: return "Codex 週次枠"
        case .codexAdditional: return "Codex Spark"
        }
    }

    /// チェック状態から、メニューバーに固定順 (claude5h, claudeWeekly, claudeScoped, codexWeekly, codexAdditional) で表示する枠の配列を決める純粋関数 (単体テスト対象)。
    static func selected(claude5h: Bool, claudeWeekly: Bool, claudeScoped: Bool, codexWeekly: Bool, codexAdditional: Bool) -> [MenuBarGaugeSelection] {
        var result: [MenuBarGaugeSelection] = []
        if claude5h { result.append(.claude5h) }
        if claudeWeekly { result.append(.claudeWeekly) }
        if claudeScoped { result.append(.claudeScoped) }
        if codexWeekly { result.append(.codexWeekly) }
        if codexAdditional { result.append(.codexAdditional) }
        return result
    }

    /// 選択中の枠の WindowUsage を取り出す純粋関数 (単体テスト対象)。未取得・失敗時は nil。
    static func window(
        for selection: MenuBarGaugeSelection,
        claude: Result<ClaudeUsage, ServiceUsageError>?,
        codex: Result<CodexUsage, ServiceUsageError>?
    ) -> WindowUsage? {
        switch selection {
        case .claude5h:
            guard case .success(let usage)? = claude else { return nil }
            return usage.fiveHour
        case .claudeWeekly:
            guard case .success(let usage)? = claude else { return nil }
            return usage.sevenDay
        case .claudeScoped:
            guard case .success(let usage)? = claude else { return nil }
            return usage.scoped?.window
        case .codexWeekly:
            guard case .success(let usage)? = codex else { return nil }
            return usage.weekly
        case .codexAdditional:
            guard case .success(let usage)? = codex else { return nil }
            return usage.additional?.window
        }
    }

    /// 選択中の枠に対応する使用率を取り出す純粋関数 (単体テスト対象)。未取得・失敗時は nil。
    static func percent(
        for selection: MenuBarGaugeSelection,
        claude: Result<ClaudeUsage, ServiceUsageError>?,
        codex: Result<CodexUsage, ServiceUsageError>?
    ) -> Double? {
        window(for: selection, claude: claude, codex: codex)?.percent
    }

    /// メニューバーの円グラフ1個ぶんの描画パラメータ。値が取れない枠は usedFraction が nil (輪郭だけの空円)。
    static func gaugeParams(
        selections: [MenuBarGaugeSelection],
        claude: Result<ClaudeUsage, ServiceUsageError>?,
        codex: Result<CodexUsage, ServiceUsageError>?,
        now: Date = Date()
    ) -> [GaugeCircleParams] {
        selections.map { selection in
            guard let w = window(for: selection, claude: claude, codex: codex) else {
                return GaugeCircleParams(usedFraction: nil, elapsedFraction: nil)
            }
            let elapsed = UsageFormat.windowPosition(
                resetsAt: w.resetsAt,
                windowSeconds: w.windowSeconds,
                usedPercent: w.percent,
                now: now
            )?.elapsed
            return GaugeCircleParams(
                usedFraction: min(max(w.percent / 100, 0), 1),
                elapsedFraction: elapsed.map { min(max($0 / 100, 0), 1) }
            )
        }
    }
}

/// メニューバーの円1個ぶんの描画パラメータ (純粋関数の出力・単体テスト対象)。
/// usedFraction が nil の場合は値が取れない枠を表し、輪郭だけの空円を描く。
struct GaugeCircleParams: Equatable {
    let usedFraction: Double?
    let elapsedFraction: Double?
}

/// worker/src/index.js の fetchClaudeUsage / mapWham を Swift に移植した純粋関数群 (単体テスト対象)。
enum UsageMapping {
    /// window_seconds がこれ以上なら週次枠、未満は5時間枠と判定する。
    static let weeklyThresholdSeconds: Double = 600_000

    static func isWeekly(windowSeconds: Double) -> Bool {
        windowSeconds >= weeklyThresholdSeconds
    }

    static func mapClaude(_ json: [String: Any]) -> ClaudeUsage {
        func window(_ dict: Any?, windowSeconds: Double) -> WindowUsage? {
            guard let d = dict as? [String: Any],
                  let percent = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return WindowUsage(percent: percent, resetsAt: parseDate(d["resets_at"]), windowSeconds: windowSeconds)
        }
        var usage = ClaudeUsage()
        usage.fiveHour = window(json["five_hour"], windowSeconds: 5 * 3600)
        usage.sevenDay = window(json["seven_day"], windowSeconds: 7 * 86400)
        if let limit = (json["limits"] as? [[String: Any]])?.first(where: { ($0["kind"] as? String) == "weekly_scoped" }),
           let percent = (limit["percent"] as? NSNumber)?.doubleValue {
            let displayName = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
            usage.scoped = NamedWindow(
                name: displayName ?? "モデル別",
                window: WindowUsage(percent: percent, resetsAt: parseDate(limit["resets_at"]), windowSeconds: 7 * 86400)
            )
        }
        return usage
    }

    static func mapWham(_ json: [String: Any]) -> CodexUsage {
        func window(_ dict: Any?) -> WindowUsage? {
            guard let d = dict as? [String: Any],
                  let percent = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let windowSeconds = (d["limit_window_seconds"] as? NSNumber)?.doubleValue ?? 0
            return WindowUsage(percent: percent, resetsAt: parseDate(d["reset_at"]), windowSeconds: windowSeconds)
        }
        let rateLimit = json["rate_limit"] as? [String: Any]
        var usage = CodexUsage()
        usage.primary = window(rateLimit?["primary_window"])
        usage.secondary = window(rateLimit?["secondary_window"])
        if let first = (json["additional_rate_limits"] as? [[String: Any]])?.first {
            let firstRateLimit = first["rate_limit"] as? [String: Any]
            if let w = window(firstRateLimit?["secondary_window"]) ?? window(firstRateLimit?["primary_window"]) {
                usage.additional = NamedWindow(name: first["limit_name"] as? String, window: w)
            }
        }
        return usage
    }

    /// resets_at / reset_at は Claude・Codex とも epoch 秒 (数値) か ISO8601 文字列のどちらかで来る。
    static func parseDate(_ value: Any?) -> Date? {
        if let n = value as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        if let s = value as? String {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFraction.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: s)
        }
        return nil
    }
}

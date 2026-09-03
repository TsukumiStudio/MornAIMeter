import Foundation

/// worker/src/index.js の履歴1点 (194〜203行、ts/c5/c7/cx/cf/cs) と同じキー名で保存する
/// 1サンプル。将来 pace() (596〜609行) をそのまま移植できるようにキー名を揃えてある。
struct HistorySample: Equatable {
    let ts: Int64
    let c5: Double?
    let c7: Double?
    let cx: Double?
    /// Claude 週次 (モデル別) 枠の使用率
    let cf: Double?
    /// Codex Spark (additional) の使用率
    let cs: Double?

    init(ts: Int64, c5: Double?, c7: Double?, cx: Double?, cf: Double? = nil, cs: Double? = nil) {
        self.ts = ts
        self.c5 = c5
        self.c7 = c7
        self.cx = cx
        self.cf = cf
        self.cs = cs
    }

    var hasValue: Bool { c5 != nil || c7 != nil || cx != nil || cf != nil || cs != nil }
}

/// ~/Library/Application Support/MornAIMeter/history.jsonl への読み書き。
/// JSON行の生成と間引きは純粋関数として分離してテストする。
enum HistoryStore {
    static let maxAgeDays: Double = 15

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MornAIMeter").appendingPathComponent("history.jsonl")
    }

    /// 1サンプルを ts/c5/c7/cx/cf/cs の JSON 行にする純粋関数。取れなかった値は null。
    static func encodeLine(_ sample: HistorySample) -> String {
        func num(_ v: Double?) -> String { v.map { "\($0)" } ?? "null" }
        return "{\"ts\":\(sample.ts),\"c5\":\(num(sample.c5)),\"c7\":\(num(sample.c7)),\"cx\":\(num(sample.cx)),\"cf\":\(num(sample.cf)),\"cs\":\(num(sample.cs))}"
    }

    /// now から maxAgeDays より古い行 (ts が読めない行も含む) を落とす純粋関数。
    static func pruneOldLines(_ lines: [String], now: Date = Date(), maxAgeDays: Double = HistoryStore.maxAgeDays) -> [String] {
        let cutoffMs = now.timeIntervalSince1970 * 1000 - maxAgeDays * 86400 * 1000
        return lines.filter { line in
            guard let ts = timestamp(of: line) else { return false }
            return Double(ts) >= cutoffMs
        }
    }

    private static func timestamp(of line: String) -> Int64? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["ts"] as? NSNumber else { return nil }
        return ts.int64Value
    }

    /// 起動時に呼ぶ。古い行を落として書き直す。失敗してもアプリの表示は止めない。
    static func pruneFileAtStartup() {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let pruned = pruneOldLines(lines)
        guard pruned.count != lines.count else { return }
        let rewritten = pruned.isEmpty ? "" : pruned.joined(separator: "\n") + "\n"
        try? rewritten.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 取得成功ごとに1行追記する。両方失敗 (全キー null) のサンプルは書かない。
    /// 追記失敗はアプリの表示に影響させない。
    static func appendSample(_ sample: HistorySample) {
        guard sample.hasValue else { return }
        let url = fileURL
        guard let data = (encodeLine(sample) + "\n").data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// 1行を HistorySample にデコードする純粋関数。pruneOldLines の timestamp(of:) と同じパーサ。
    static func decodeLine(_ line: String) -> HistorySample? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = (obj["ts"] as? NSNumber)?.int64Value else { return nil }
        func num(_ key: String) -> Double? { (obj[key] as? NSNumber)?.doubleValue }
        return HistorySample(ts: ts, c5: num("c5"), c7: num("c7"), cx: num("cx"), cf: num("cf"), cs: num("cs"))
    }

    /// 直近 maxAgeDays 分のサンプルを時系列順に読み出す。読めない行はスキップする。
    static func readRecentSamples(now: Date = Date(), maxAgeDays: Double = HistoryStore.maxAgeDays) -> [HistorySample] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let pruned = pruneOldLines(lines, now: now, maxAgeDays: maxAgeDays)
        return pruned.compactMap(decodeLine)
    }
}

/// MornUsage worker/src/index.js の blockCost の移植。
/// 5時間枠フル1回 (0% -> 100%) を使い切ると週次枠が何 %pt 減るかを、直近の履歴から推定する。
enum BlockCost {
    static let periodDays: Double = 14
    static let maxGapMinutes: Double = 45

    /// samples から c5 と weeklyKey (\.c7 または \.cf) が両方 non-null の点を時系列順に抽出し、
    /// 隣接ペアごとに 45分超ギャップ・リセットまたぎ (増分が負) を除外して積算する。
    /// usedFive が 100 未満、または usedWeekly が 0 以下なら nil。
    static func estimate(
        samples: [HistorySample],
        weeklyKey: (HistorySample) -> Double?,
        now: Date = Date(),
        periodDays: Double = BlockCost.periodDays,
        maxGapMinutes: Double = BlockCost.maxGapMinutes
    ) -> Double? {
        let cutoffMs = now.timeIntervalSince1970 * 1000 - periodDays * 86400 * 1000
        let points: [(ts: Int64, c5: Double, weekly: Double)] = samples
            .filter { Double($0.ts) >= cutoffMs }
            .compactMap { sample in
                guard let c5 = sample.c5, let weekly = weeklyKey(sample) else { return nil }
                return (sample.ts, c5, weekly)
            }
            .sorted { $0.ts < $1.ts }

        guard points.count >= 2 else { return nil }

        let maxGapMs = maxGapMinutes * 60 * 1000
        var usedFive: Double = 0
        var usedWeekly: Double = 0
        for i in 1..<points.count {
            let prev = points[i - 1]
            let cur = points[i]
            let gapMs = Double(cur.ts - prev.ts)
            guard gapMs <= maxGapMs else { continue }
            let d5 = cur.c5 - prev.c5
            let dw = cur.weekly - prev.weekly
            guard d5 >= 0, dw >= 0 else { continue }
            usedFive += d5
            usedWeekly += dw
        }

        guard usedFive >= 100, usedWeekly > 0 else { return nil }
        return usedWeekly / usedFive * 100
    }

    /// worker/src/index.js の blockTicks の移植。used から cost きざみで 99.5 未満の間、区切り線の x 位置 (%) を並べる。
    static func ticks(used: Double, cost: Double) -> [Double] {
        guard cost > 0.5 else { return [] }
        var result: [Double] = []
        var x = used + cost
        while x < 99.5 {
            result.append(x)
            x += cost
        }
        return result
    }

    /// worker/src/index.js の blockHint の移植。「5時間枠フル1回 ≒ X%pt ・ 残り約 N 回ぶん」。
    static func hint(used: Double, cost: Double) -> String {
        let remaining = max(0, 100 - used) / cost
        let remainingText = remaining < 10 ? String(format: "%.1f", remaining) : String(format: "%.0f", remaining)
        return "5時間枠フル1回 ≒ " + String(format: "%.0f", cost) + "%pt ・ 残り約 " + remainingText + " 回ぶん"
    }
}

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
}

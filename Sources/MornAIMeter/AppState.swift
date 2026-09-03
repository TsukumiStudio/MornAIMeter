import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var claudeResult: Result<ClaudeUsage, ServiceUsageError>?
    @Published private(set) var codexResult: Result<CodexUsage, ServiceUsageError>?
    @Published private(set) var lastGoodClaude: ClaudeUsage?
    @Published private(set) var lastGoodCodex: CodexUsage?
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 5 * 60
    private let minFetchInterval: TimeInterval = 60

    private var lastFetchedAtClaude: Date?
    private var lastFetchedAtCodex: Date?
    private var retryNotBeforeClaude: Date?
    private var retryNotBeforeCodex: Date?

    init() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 取得すべきかどうかを判定する純粋関数 (単体テスト対象)。
    /// retryNotBefore が未来なら force でもスキップ、それ以外は force か 60秒未満はスキップ。
    nonisolated static func shouldFetch(now: Date, lastFetchedAt: Date?, retryNotBefore: Date?, minInterval: TimeInterval, force: Bool) -> Bool {
        if let retryNotBefore, now < retryNotBefore { return false }
        if force { return true }
        guard let lastFetchedAt else { return true }
        return now.timeIntervalSince(lastFetchedAt) >= minInterval
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        let now = Date()
        let fetchClaude = Self.shouldFetch(now: now, lastFetchedAt: lastFetchedAtClaude, retryNotBefore: retryNotBeforeClaude, minInterval: minFetchInterval, force: force)
        let fetchCodex = Self.shouldFetch(now: now, lastFetchedAt: lastFetchedAtCodex, retryNotBefore: retryNotBeforeCodex, minInterval: minFetchInterval, force: force)
        guard fetchClaude || fetchCodex else { return }
        isRefreshing = true
        Task {
            async let claudeTask: Result<ClaudeUsage, ServiceUsageError>? = {
                guard fetchClaude else { return nil }
                return await UsageFetcher.fetchClaude()
            }()
            async let codexTask: Result<CodexUsage, ServiceUsageError>? = {
                guard fetchCodex else { return nil }
                return await UsageFetcher.fetchCodex()
            }()
            let claude = await claudeTask
            let codex = await codexTask
            if let claude {
                claudeResult = claude
                lastFetchedAtClaude = Date()
                switch claude {
                case .success(let usage):
                    lastGoodClaude = usage
                    retryNotBeforeClaude = nil
                case .failure(.network(_, let retryNotBefore)):
                    if let retryNotBefore { retryNotBeforeClaude = retryNotBefore }
                case .failure(.needsLogin):
                    break
                }
            }
            if let codex {
                codexResult = codex
                lastFetchedAtCodex = Date()
                switch codex {
                case .success(let usage):
                    lastGoodCodex = usage
                    retryNotBeforeCodex = nil
                case .failure(.network(_, let retryNotBefore)):
                    if let retryNotBefore { retryNotBeforeCodex = retryNotBefore }
                case .failure(.needsLogin):
                    break
                }
            }
            isRefreshing = false
        }
    }
}

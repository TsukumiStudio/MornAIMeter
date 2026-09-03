import SwiftUI

struct UsageCardView: View {
    enum Content {
        case data(percent: Double, resetText: String, position: WindowPosition?, errorMessage: String? = nil, blockCost: Double? = nil)
        case noData
        case message(String)
    }

    let title: String
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch content {
            case .data(let percent, let resetText, let position, let errorMessage, let blockCost):
                let remaining = max(0, 100 - percent)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.caption.bold())
                    Spacer(minLength: 4)
                    if let position {
                        Text(UsageFormat.paceLabel(position.difference))
                            .font(.caption2)
                            .foregroundStyle(position.difference > 1 ? .red : .secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f%%", remaining))
                        .font(.title3.monospacedDigit())
                    Text("残り")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(String(format: "%.0f%% 使用", percent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(percent, 0), 100), total: 100)
                    // 5時間枠フル1回ぶんの区切り線 (バー背景色と同じ色でバーの塗りを分断する)。経過率の線より背面。
                    .overlay(alignment: .leading) {
                        if let blockCost {
                            GeometryReader { geo in
                                ForEach(BlockCost.ticks(used: percent, cost: blockCost), id: \.self) { x in
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.12))
                                        .frame(width: 2)
                                        .offset(x: max(0, geo.size.width * x / 100 - 1))
                                }
                            }
                        }
                    }
                    // 枠の経過率の位置を示す縦の目盛り線 (resets_at が無ければ position は nil)
                    .overlay(alignment: .leading) {
                        if let position {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.primary.opacity(0.8))
                                    .frame(width: 1)
                                    .offset(x: max(0, geo.size.width * position.elapsed / 100 - 0.5))
                            }
                        }
                    }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(resetText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let position {
                        Text("経過 " + String(format: "%.0f", position.elapsed) + "%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let blockCost {
                    Text(BlockCost.hint(used: percent, cost: blockCost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            case .noData:
                Text(title).font(.caption.bold())
                Text("データなし")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .message(let message):
                Text(title).font(.caption.bold())
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
    }
}

private func cardContent(percent: Double, resetsAt: Date?, windowSeconds: Double, errorMessage: String? = nil, blockCost: Double? = nil) -> UsageCardView.Content {
    .data(
        percent: percent,
        resetText: UsageFormat.resetText(resetsAt: resetsAt, windowSeconds: windowSeconds),
        position: UsageFormat.windowPosition(resetsAt: resetsAt, windowSeconds: windowSeconds, usedPercent: percent),
        errorMessage: errorMessage,
        blockCost: blockCost
    )
}

/// 直前の成功値があればそれを表示し続け、最新が失敗ならその値の下にエラー文を併記する。
/// 成功値が一度も無いときだけエラー文単独 (.message) を返す。
private func claudeCardContent(
    _ result: Result<ClaudeUsage, ServiceUsageError>?,
    lastGood: ClaudeUsage?,
    blockCost: Double? = nil,
    _ window: (ClaudeUsage) -> WindowUsage?
) -> UsageCardView.Content {
    if let good = lastGood, let w = window(good) {
        let errorMessage: String? = { if case .failure(let error)? = result { return error.errorDescription ?? "取得失敗" }; return nil }()
        return cardContent(percent: w.percent, resetsAt: w.resetsAt, windowSeconds: w.windowSeconds, errorMessage: errorMessage, blockCost: blockCost)
    }
    guard let result else { return .noData }
    switch result {
    case .failure(let error):
        return .message(error.errorDescription ?? "取得失敗")
    case .success(let usage):
        guard let w = window(usage) else { return .noData }
        return cardContent(percent: w.percent, resetsAt: w.resetsAt, windowSeconds: w.windowSeconds, blockCost: blockCost)
    }
}

private func codexCardContent(
    _ result: Result<CodexUsage, ServiceUsageError>?,
    lastGood: CodexUsage?,
    _ window: (CodexUsage) -> WindowUsage?
) -> UsageCardView.Content {
    if let good = lastGood, let w = window(good) {
        let errorMessage: String? = { if case .failure(let error)? = result { return error.errorDescription ?? "取得失敗" }; return nil }()
        return cardContent(percent: w.percent, resetsAt: w.resetsAt, windowSeconds: w.windowSeconds, errorMessage: errorMessage)
    }
    guard let result else { return .noData }
    switch result {
    case .failure(let error):
        return .message(error.errorDescription ?? "取得失敗")
    case .success(let usage):
        guard let w = window(usage) else { return .noData }
        return cardContent(percent: w.percent, resetsAt: w.resetsAt, windowSeconds: w.windowSeconds)
    }
}

/// 直前成功値 → 現在の成功値の順で、scoped/additional の名前を探す。両方無ければ nil。
private func scopedName(_ result: Result<ClaudeUsage, ServiceUsageError>?, lastGood: ClaudeUsage?) -> String? {
    if let name = lastGood?.scoped?.name { return name }
    if case .success(let usage)? = result { return usage.scoped?.name }
    return nil
}

struct PopoverContentView: View {
    @ObservedObject var state: AppState
    @AppStorage("menuBarShowClaude5h") private var showClaude5h = true
    @AppStorage("menuBarShowClaudeWeekly") private var showClaudeWeekly = false
    @AppStorage("menuBarShowClaudeScoped") private var showClaudeScoped = false
    @AppStorage("menuBarShowCodexWeekly") private var showCodexWeekly = false
    @AppStorage("menuBarShowCodexAdditional") private var showCodexAdditional = false
    @StateObject private var loginItem = LoginItemState()

    private static let rowHeadingWidth: CGFloat = 74

    private var appVersionText: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        return "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("Claude").font(.caption).foregroundStyle(.secondary).frame(width: Self.rowHeadingWidth, alignment: .leading)
                HStack(spacing: 8) {
                    UsageCardView(title: "5時間枠", content: claudeCardContent(state.claudeResult, lastGood: state.lastGoodClaude) { $0.fiveHour })
                    UsageCardView(title: "週次枠", content: claudeCardContent(state.claudeResult, lastGood: state.lastGoodClaude, blockCost: state.weeklyBlockCost) { $0.sevenDay })
                    UsageCardView(
                        title: "週次 (\(scopedName(state.claudeResult, lastGood: state.lastGoodClaude) ?? "Fable"))",
                        content: claudeCardContent(state.claudeResult, lastGood: state.lastGoodClaude, blockCost: state.scopedBlockCost) { $0.scoped?.window }
                    )
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Text("Codex").font(.caption).foregroundStyle(.secondary).frame(width: Self.rowHeadingWidth, alignment: .leading)
                HStack(spacing: 8) {
                    UsageCardView(title: "週次枠", content: codexCardContent(state.codexResult, lastGood: state.lastGoodCodex) { $0.weekly })
                    UsageCardView(
                        title: "Codex Spark",
                        content: codexCardContent(state.codexResult, lastGood: state.lastGoodCodex) { $0.additional?.window }
                    )
                }
            }

            Divider()

            Text("メニューバー表示").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Toggle(MenuBarGaugeSelection.claude5h.label, isOn: $showClaude5h)
                Toggle(MenuBarGaugeSelection.claudeWeekly.label, isOn: $showClaudeWeekly)
                Toggle(MenuBarGaugeSelection.claudeScoped.label(scopedName: scopedName(state.claudeResult, lastGood: state.lastGoodClaude)), isOn: $showClaudeScoped)
                Toggle(MenuBarGaugeSelection.codexWeekly.label, isOn: $showCodexWeekly)
                Toggle(MenuBarGaugeSelection.codexAdditional.label, isOn: $showCodexAdditional)
            }

            Divider()

            HStack(spacing: 8) {
                Button("終了") {
                    NSApp.terminate(nil)
                }
                Button("GitHub で開く") {
                    if let url = URL(string: AppLinks.repository) {
                        NSWorkspace.shared.open(url)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("ログイン時に起動", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    if let errorMessage = loginItem.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if loginItem.requiresApproval {
                        Text("システム設定 の ログイン項目 で許可が必要")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(appVersionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 720)
        .onAppear {
            state.refresh()
            loginItem.refresh()
        }
    }
}

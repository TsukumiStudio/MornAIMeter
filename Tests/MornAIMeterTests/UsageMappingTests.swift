import AppKit
import XCTest
@testable import MornAIMeter

final class UsageMappingTests: XCTestCase {
    // MARK: - Claude

    func testMapClaudeExtractsFiveHourAndSevenDay() throws {
        let json: [String: Any] = [
            "five_hour": ["utilization": 42.5, "resets_at": "2026-09-02T12:00:00Z"],
            "seven_day": ["utilization": 10.0, "resets_at": 1_777_776_000],
        ]
        let usage = UsageMapping.mapClaude(json)

        let fiveHour = try XCTUnwrap(usage.fiveHour)
        XCTAssertEqual(fiveHour.percent, 42.5)
        XCTAssertEqual(fiveHour.windowSeconds, 5 * 3600)
        XCTAssertEqual(fiveHour.resetsAt, ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z"))

        let sevenDay = try XCTUnwrap(usage.sevenDay)
        XCTAssertEqual(sevenDay.percent, 10.0)
        XCTAssertEqual(sevenDay.windowSeconds, 7 * 86400)
        XCTAssertEqual(sevenDay.resetsAt, Date(timeIntervalSince1970: 1_777_776_000))
    }

    func testMapClaudeMissingWindowIsNil() {
        let usage = UsageMapping.mapClaude(["five_hour": ["utilization": 1.0]])
        XCTAssertNotNil(usage.fiveHour)
        XCTAssertNil(usage.sevenDay)
    }

    // MARK: - Codex

    func testMapWhamExtractsPrimaryAndSecondary() throws {
        let json: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 33.3, "limit_window_seconds": 18_000, "reset_at": "2026-09-02T09:00:00Z"],
                "secondary_window": ["used_percent": 12.1, "limit_window_seconds": 604_800, "reset_at": 1_777_776_000],
            ]
        ]
        let usage = UsageMapping.mapWham(json)

        let primary = try XCTUnwrap(usage.primary)
        XCTAssertEqual(primary.percent, 33.3)
        XCTAssertEqual(primary.windowSeconds, 18_000)

        let secondary = try XCTUnwrap(usage.secondary)
        XCTAssertEqual(secondary.percent, 12.1)
        XCTAssertEqual(secondary.windowSeconds, 604_800)
    }

    func testWindowSecondsJudgesFiveHourVsWeekly() {
        // window_seconds が 600000 以上なら週次枠、未満は5時間枠
        XCTAssertFalse(UsageMapping.isWeekly(windowSeconds: 18_000))
        XCTAssertFalse(UsageMapping.isWeekly(windowSeconds: 599_999))
        XCTAssertTrue(UsageMapping.isWeekly(windowSeconds: 600_000))
        XCTAssertTrue(UsageMapping.isWeekly(windowSeconds: 604_800))
    }

    func testMapClaudeExtractsFirstWeeklyScopedLimit() throws {
        let json: [String: Any] = [
            "limits": [
                ["kind": "other", "percent": 5.0],
                ["kind": "weekly_scoped", "percent": 33.0, "resets_at": 1_777_776_000, "scope": ["model": ["display_name": "Fable"]]],
                ["kind": "weekly_scoped", "percent": 99.0, "resets_at": 1_777_776_000],
            ]
        ]
        let usage = UsageMapping.mapClaude(json)
        let scoped = try XCTUnwrap(usage.scoped)
        XCTAssertEqual(scoped.name, "Fable")
        XCTAssertEqual(scoped.window.percent, 33.0)
        XCTAssertEqual(scoped.window.windowSeconds, 7 * 86400)
    }

    func testMapClaudeScopedMissingDisplayNameFallsBackToFable() throws {
        let json: [String: Any] = [
            "limits": [
                ["kind": "weekly_scoped", "percent": 12.0, "resets_at": 1_777_776_000],
            ]
        ]
        let usage = UsageMapping.mapClaude(json)
        XCTAssertEqual(try XCTUnwrap(usage.scoped).name, "Fable")
    }

    func testMapClaudeMissingScopedIsNil() {
        XCTAssertNil(UsageMapping.mapClaude(["five_hour": ["utilization": 1.0]]).scoped)
    }

    func testMapWhamAdditionalPrefersSecondaryWindowOverPrimary() throws {
        let json: [String: Any] = [
            "additional_rate_limits": [
                ["limit_name": "GPT-5.3-Codex-Spark", "rate_limit": [
                    "primary_window": ["used_percent": 44.0, "limit_window_seconds": 18_000, "reset_at": 1_777_776_000],
                    "secondary_window": ["used_percent": 12.0, "limit_window_seconds": 604_800, "reset_at": 1_777_776_000],
                ]],
            ]
        ]
        let usage = UsageMapping.mapWham(json)
        let additional = try XCTUnwrap(usage.additional)
        XCTAssertEqual(additional.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(additional.window.percent, 12.0)
        XCTAssertEqual(additional.window.windowSeconds, 604_800)
    }

    func testMapWhamAdditionalFallsBackToPrimaryWhenSecondaryMissing() throws {
        let json: [String: Any] = [
            "additional_rate_limits": [
                ["limit_name": "GPT-5.3-Codex-Spark", "rate_limit": ["primary_window": ["used_percent": 44.0, "limit_window_seconds": 18_000, "reset_at": 1_777_776_000]]],
            ]
        ]
        let usage = UsageMapping.mapWham(json)
        let additional = try XCTUnwrap(usage.additional)
        XCTAssertEqual(additional.window.percent, 44.0)
        XCTAssertEqual(additional.window.windowSeconds, 18_000)
    }

    func testMapWhamAdditionalMissingNameIsNilNotFallback() throws {
        let json: [String: Any] = [
            "additional_rate_limits": [
                ["rate_limit": ["primary_window": ["used_percent": 7.0, "limit_window_seconds": 604_800, "reset_at": 1_777_776_000]]],
            ]
        ]
        let usage = UsageMapping.mapWham(json)
        XCTAssertNil(try XCTUnwrap(usage.additional).name)
    }

    func testMapWhamMissingAdditionalIsNil() {
        XCTAssertNil(UsageMapping.mapWham(["rate_limit": [:]]).additional)
    }

    func testCodexUsageFiveHourAndWeeklyPickByWindowSeconds() throws {
        let json: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 33.3, "limit_window_seconds": 18_000, "reset_at": 1_777_776_000],
                "secondary_window": ["used_percent": 12.1, "limit_window_seconds": 604_800, "reset_at": 1_777_776_000],
            ]
        ]
        let usage = UsageMapping.mapWham(json)
        XCTAssertEqual(try XCTUnwrap(usage.fiveHour).windowSeconds, 18_000)
        XCTAssertEqual(try XCTUnwrap(usage.weekly).windowSeconds, 604_800)
    }

    // MARK: - Antigravity

    func testMapAntigravitySampleResponse() throws {
        let json: [String: Any] = [
            "groups": [
                [
                    "displayName": "Gemini Models",
                    "description": "...",
                    "buckets": [
                        ["bucketId": "gemini-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly", "resetTime": "2026-09-05T10:09:14Z", "remainingFraction": 0.9089336],
                    ],
                ],
                [
                    "displayName": "Claude and GPT models",
                    "buckets": [
                        ["bucketId": "3p-weekly", "window": "weekly", "resetTime": "2026-09-10T10:06:55Z", "remainingFraction": 1],
                    ],
                ],
            ],
            "description": "...",
        ]
        let usage = UsageMapping.mapAntigravity(json)

        let gemini = try XCTUnwrap(usage.gemini)
        XCTAssertEqual(gemini.percent, 9.10664, accuracy: 0.01)
        XCTAssertEqual(gemini.windowSeconds, 604_800)
        XCTAssertEqual(gemini.resetsAt, ISO8601DateFormatter().date(from: "2026-09-05T10:09:14Z"))

        let claudeGpt = try XCTUnwrap(usage.claudeGpt)
        XCTAssertEqual(claudeGpt.percent, 0, accuracy: 0.01)
    }

    func testMapAntigravityFallsBackToDisplayNameWhenBucketIdUnknown() throws {
        let json: [String: Any] = [
            "groups": [
                ["displayName": "Gemini Models", "buckets": [["bucketId": "unknown", "window": "weekly", "remainingFraction": 0.5]]],
                ["displayName": "Claude and GPT models", "buckets": [["bucketId": "unknown", "window": "weekly", "remainingFraction": 0.2]]],
            ]
        ]
        let usage = UsageMapping.mapAntigravity(json)
        XCTAssertEqual(try XCTUnwrap(usage.gemini).percent, 50, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(usage.claudeGpt).percent, 80, accuracy: 0.01)
    }

    func testMapAntigravityMissingRemainingFractionIsNil() {
        let json: [String: Any] = [
            "groups": [
                ["displayName": "Gemini Models", "buckets": [["bucketId": "gemini-weekly", "window": "weekly"]]],
            ]
        ]
        let usage = UsageMapping.mapAntigravity(json)
        XCTAssertNil(usage.gemini)
        XCTAssertNil(usage.claudeGpt)
    }

    // MARK: - Credentials: Antigravity expiry

    func testParseExpiryWithFractionalSeconds() throws {
        // 日本時間 (+09:00) の小数秒付き文字列が UTC の同時刻へ正しく変換されることを確認する。
        let date = try XCTUnwrap(Credentials.parseExpiry("2026-09-03T19:23:38.905747+09:00"))
        let utc = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-03T10:23:38Z"))
        XCTAssertEqual(date.timeIntervalSince1970, utc.timeIntervalSince1970, accuracy: 1.0)
    }

    func testParseExpiryWithoutFractionalSeconds() throws {
        let date = try XCTUnwrap(Credentials.parseExpiry("2026-09-03T10:23:38Z"))
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-09-03T10:23:38Z"))
    }

    // MARK: - Formatting: remain

    func testRemainMinutesOnly() {
        XCTAssertEqual(UsageFormat.remain(59 * 60), "あと59分")
    }

    func testRemainHourBoundary() {
        // 61分 -> 1時間1分
        XCTAssertEqual(UsageFormat.remain(61 * 60), "あと1時間1分")
    }

    func testRemainDayBoundary() {
        // 1日以上は分を省いて日・時間のみ
        XCTAssertEqual(UsageFormat.remain(4 * 86400 + 11 * 3600 + 39 * 60), "あと4日11時間")
    }

    func testRemainExactDayNoHours() {
        // 24時間ちょうど -> hoursが0なので日のみ
        XCTAssertEqual(UsageFormat.remain(24 * 3600), "あと1日")
    }

    func testRemainHoursAndMinutesUnderOneDay() {
        XCTAssertEqual(UsageFormat.remain(4 * 3600 + 9 * 60), "あと4時間9分")
    }

    // MARK: - Formatting: resetText

    func testResetTextFutureDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(3660) // 1時間1分後
        let text = UsageFormat.resetText(resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now)
        XCTAssertEqual(text, "あと1時間1分でリセット")
    }

    func testResetTextPastDateEstimatesNextWindow() {
        // 5時間枠 (18000秒) が2時間前に切れていたら、次は3時間後
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(-2 * 3600)
        let text = UsageFormat.resetText(resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now)
        XCTAssertEqual(text, "次回まであと3時間0分")
    }

    func testResetTextNilResetsAt() {
        XCTAssertEqual(UsageFormat.resetText(resetsAt: nil, windowSeconds: 5 * 3600), "リセット時刻不明")
    }

    // MARK: - MenuBarGaugeSelection

    func testMenuBarGaugeSelectionPicksPercentByCase() throws {
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(
            ClaudeUsage(
                fiveHour: WindowUsage(percent: 42, resetsAt: nil, windowSeconds: 18_000),
                sevenDay: WindowUsage(percent: 10, resetsAt: nil, windowSeconds: 604_800)
            )
        )
        var codex = CodexUsage()
        codex.primary = WindowUsage(percent: 5, resetsAt: nil, windowSeconds: 18_000)
        codex.secondary = WindowUsage(percent: 77, resetsAt: nil, windowSeconds: 604_800)
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(codex)

        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .claude5h, claude: claude, codex: codexResult), 42)
        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .claudeWeekly, claude: claude, codex: codexResult), 10)
        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .codexWeekly, claude: claude, codex: codexResult), 77)
    }

    func testMenuBarGaugeSelectionNilWhenUnavailableOrFailed() {
        XCTAssertNil(MenuBarGaugeSelection.percent(for: .claude5h, claude: nil, codex: nil))
        XCTAssertNil(MenuBarGaugeSelection.percent(
            for: .claude5h,
            claude: .failure(.network("エラー")),
            codex: nil
        ))
        XCTAssertNil(MenuBarGaugeSelection.percent(
            for: .codexWeekly,
            claude: nil,
            codex: .failure(.needsLogin("codex login"))
        ))
    }

    func testMenuBarGaugeSelectionPicksScopedAndAdditionalPercent() throws {
        var claudeUsage = ClaudeUsage()
        claudeUsage.scoped = NamedWindow(name: "Fable", window: WindowUsage(percent: 33, resetsAt: nil, windowSeconds: 7 * 86400))
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(claudeUsage)

        var codexUsage = CodexUsage()
        codexUsage.additional = NamedWindow(name: "Spark", window: WindowUsage(percent: 44, resetsAt: nil, windowSeconds: 604_800))
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(codexUsage)

        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .claudeScoped, claude: claude, codex: codexResult), 33)
        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .codexAdditional, claude: claude, codex: codexResult), 44)
    }

    func testMenuBarGaugeSelectionScopedAndAdditionalNilWhenMissing() {
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(ClaudeUsage())
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(CodexUsage())
        XCTAssertNil(MenuBarGaugeSelection.percent(for: .claudeScoped, claude: claude, codex: codexResult))
        XCTAssertNil(MenuBarGaugeSelection.percent(for: .codexAdditional, claude: claude, codex: codexResult))
    }

    func testMenuBarGaugeSelectionSelectedAllThreeKeepsFixedOrder() {
        XCTAssertEqual(
            MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: true, claudeScoped: false, codexWeekly: true, codexAdditional: false),
            [.claude5h, .claudeWeekly, .codexWeekly]
        )
    }

    func testMenuBarGaugeSelectionSelectedAllFiveKeepsFixedOrder() {
        XCTAssertEqual(
            MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: true, claudeScoped: true, codexWeekly: true, codexAdditional: true),
            [.claude5h, .claudeWeekly, .claudeScoped, .codexWeekly, .codexAdditional]
        )
    }

    func testMenuBarGaugeSelectionSelectedOnlyOne() {
        XCTAssertEqual(
            MenuBarGaugeSelection.selected(claude5h: false, claudeWeekly: true, claudeScoped: false, codexWeekly: false, codexAdditional: false),
            [.claudeWeekly]
        )
    }

    func testMenuBarGaugeSelectionSelectedAntigravityTrailsFixedOrder() {
        XCTAssertEqual(
            MenuBarGaugeSelection.selected(
                claude5h: true,
                claudeWeekly: false,
                claudeScoped: false,
                codexWeekly: false,
                codexAdditional: false,
                antigravityGemini: true,
                antigravityClaudeGpt: true
            ),
            [.claude5h, .antigravityGemini, .antigravityClaudeGpt]
        )
    }

    func testMenuBarGaugeSelectionAntigravityPercent() throws {
        let antigravity = Result<AntigravityUsage, ServiceUsageError>.success(
            AntigravityUsage(
                gemini: WindowUsage(percent: 9, resetsAt: nil, windowSeconds: 604_800),
                claudeGpt: WindowUsage(percent: 0, resetsAt: nil, windowSeconds: 604_800)
            )
        )
        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .antigravityGemini, claude: nil, codex: nil, antigravity: antigravity), 9)
        XCTAssertEqual(MenuBarGaugeSelection.percent(for: .antigravityClaudeGpt, claude: nil, codex: nil, antigravity: antigravity), 0)
        XCTAssertNil(MenuBarGaugeSelection.percent(for: .antigravityGemini, claude: nil, codex: nil, antigravity: nil))
    }

    func testMenuBarGaugeSelectionSelectedNoneIsEmpty() {
        XCTAssertEqual(
            MenuBarGaugeSelection.selected(claude5h: false, claudeWeekly: false, claudeScoped: false, codexWeekly: false, codexAdditional: false),
            []
        )
    }

    func testGaugeParamsOrdersThreeSelectionsWithFractions() {
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(
            ClaudeUsage(
                fiveHour: WindowUsage(percent: 20, resetsAt: nil, windowSeconds: 18_000),
                sevenDay: WindowUsage(percent: 3, resetsAt: nil, windowSeconds: 604_800)
            )
        )
        var codex = CodexUsage()
        codex.secondary = WindowUsage(percent: 50, resetsAt: nil, windowSeconds: 604_800)
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(codex)

        let params = MenuBarGaugeSelection.gaugeParams(
            selections: MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: true, claudeScoped: false, codexWeekly: true, codexAdditional: false),
            claude: claude,
            codex: codexResult
        )
        XCTAssertEqual(params.map(\.usedFraction), [0.2, 0.03, 0.5])
        XCTAssertEqual(params.map(\.elapsedFraction), [nil, nil, nil])
    }

    func testGaugeParamsAllFiveSelectionsKeepFixedOrder() {
        var claudeUsage = ClaudeUsage(
            fiveHour: WindowUsage(percent: 20, resetsAt: nil, windowSeconds: 18_000),
            sevenDay: WindowUsage(percent: 3, resetsAt: nil, windowSeconds: 604_800)
        )
        claudeUsage.scoped = NamedWindow(name: "Fable", window: WindowUsage(percent: 33, resetsAt: nil, windowSeconds: 7 * 86400))
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(claudeUsage)

        var codexUsage = CodexUsage()
        codexUsage.secondary = WindowUsage(percent: 0, resetsAt: nil, windowSeconds: 604_800)
        codexUsage.additional = NamedWindow(name: "Spark", window: WindowUsage(percent: 44, resetsAt: nil, windowSeconds: 604_800))
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(codexUsage)

        let params = MenuBarGaugeSelection.gaugeParams(
            selections: MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: true, claudeScoped: true, codexWeekly: true, codexAdditional: true),
            claude: claude,
            codex: codexResult
        )
        XCTAssertEqual(params.map(\.usedFraction), [0.2, 0.03, 0.33, 0, 0.44])
    }

    func testGaugeParamsNoSelectionIsEmpty() {
        let params = MenuBarGaugeSelection.gaugeParams(
            selections: MenuBarGaugeSelection.selected(claude5h: false, claudeWeekly: false, claudeScoped: false, codexWeekly: false, codexAdditional: false),
            claude: nil,
            codex: nil
        )
        XCTAssertEqual(params, [])
    }

    func testGaugeParamsUnavailableWindowIsEmptyCircle() {
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(
            ClaudeUsage(
                fiveHour: WindowUsage(percent: 20, resetsAt: nil, windowSeconds: 18_000),
                sevenDay: nil
            )
        )
        var codex = CodexUsage()
        codex.secondary = WindowUsage(percent: 0, resetsAt: nil, windowSeconds: 604_800)
        let codexResult = Result<CodexUsage, ServiceUsageError>.success(codex)

        let params = MenuBarGaugeSelection.gaugeParams(
            selections: MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: true, claudeScoped: false, codexWeekly: true, codexAdditional: false),
            claude: claude,
            codex: codexResult
        )
        XCTAssertEqual(params[0].usedFraction, 0.2)
        XCTAssertNil(params[1].usedFraction)
        XCTAssertEqual(params[2].usedFraction, 0)
    }

    func testGaugeParamsComputesElapsedFractionFromWindowPosition() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(1800) // 半分経過 (windowSeconds 3600)
        let claude = Result<ClaudeUsage, ServiceUsageError>.success(
            ClaudeUsage(fiveHour: WindowUsage(percent: 20, resetsAt: resetsAt, windowSeconds: 3600))
        )
        let params = MenuBarGaugeSelection.gaugeParams(
            selections: MenuBarGaugeSelection.selected(claude5h: true, claudeWeekly: false, claudeScoped: false, codexWeekly: false, codexAdditional: false),
            claude: claude,
            codex: nil,
            now: now
        )
        XCTAssertEqual(params[0].elapsedFraction!, 0.5, accuracy: 0.0001)
    }

    // MARK: - GaugeImage

    func testGaugeImageSizeForOneCircle() {
        let image = GaugeImage.make(params: [GaugeCircleParams(usedFraction: 0.2, elapsedFraction: nil)])
        XCTAssertEqual(image.size, NSSize(width: GaugeImage.diameter, height: GaugeImage.diameter))
        XCTAssertFalse(image.isTemplate)
    }

    func testGaugeImageSizeForThreeCircles() {
        let image = GaugeImage.make(params: [
            GaugeCircleParams(usedFraction: 0.2, elapsedFraction: 0.1),
            GaugeCircleParams(usedFraction: nil, elapsedFraction: nil),
            GaugeCircleParams(usedFraction: 0, elapsedFraction: 0.9),
        ])
        let expectedWidth = 3 * GaugeImage.diameter + 2 * GaugeImage.spacing
        XCTAssertEqual(image.size, NSSize(width: expectedWidth, height: GaugeImage.diameter))
    }

    // MARK: - Formatting: percentText

    func testPercentTextShowsDashWhenNil() {
        XCTAssertEqual(UsageFormat.percentText(nil), "--")
    }

    func testPercentTextFormatsWholeNumberPercent() {
        XCTAssertEqual(UsageFormat.percentText(42), "42%")
    }

    // MARK: - Formatting: windowPosition

    func testWindowPositionFutureResetsAt() {
        // 5時間枠 (18000秒)、リセットまで1時間 -> 経過4時間ぶん = 80%
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(3600)
        let position = try! XCTUnwrap(UsageFormat.windowPosition(resetsAt: resetsAt, windowSeconds: 5 * 3600, usedPercent: 90, now: now))
        XCTAssertEqual(position.elapsed, 80, accuracy: 0.01)
        XCTAssertEqual(position.difference, 10, accuracy: 0.01)
    }

    func testWindowPositionPastResetsAtAdvancesToCurrentWindow() {
        // 5時間枠が2時間前に切れていた (=次の枠は3時間後) -> 経過2時間ぶん = 40%
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(-2 * 3600)
        let position = try! XCTUnwrap(UsageFormat.windowPosition(resetsAt: resetsAt, windowSeconds: 5 * 3600, usedPercent: 30, now: now))
        XCTAssertEqual(position.elapsed, 40, accuracy: 0.01)
        XCTAssertEqual(position.difference, -10, accuracy: 0.01)
    }

    func testWindowPositionElapsedClampedTo0And100() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // ちょうどリセット直後 (elapsed 0)
        let justReset = try! XCTUnwrap(UsageFormat.windowPosition(resetsAt: now, windowSeconds: 5 * 3600, usedPercent: 0, now: now))
        XCTAssertEqual(justReset.elapsed, 0, accuracy: 0.01)
        // ちょうどリセット直前 (elapsed 100 に近い、100を超えない)
        let almostDue = try! XCTUnwrap(UsageFormat.windowPosition(resetsAt: now.addingTimeInterval(1), windowSeconds: 5 * 3600, usedPercent: 0, now: now))
        XCTAssertLessThanOrEqual(almostDue.elapsed, 100)
    }

    func testWindowPositionNilWhenInputsMissing() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(UsageFormat.windowPosition(resetsAt: nil, windowSeconds: 5 * 3600, usedPercent: 50, now: now))
        XCTAssertNil(UsageFormat.windowPosition(resetsAt: now, windowSeconds: 0, usedPercent: 50, now: now))
        XCTAssertNil(UsageFormat.windowPosition(resetsAt: now, windowSeconds: 5 * 3600, usedPercent: nil, now: now))
    }

    // MARK: - Credentials

    func testParseClaudeAccessTokenFromSecurityOutputWithTrailingNewline() throws {
        let output = "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-abc123\"}}\n"
        let token = try Credentials.parseClaudeAccessToken(fromSecurityOutput: output)
        XCTAssertEqual(token, "sk-ant-abc123")
    }

    func testParseClaudeAccessTokenFromInvalidJSONThrows() {
        XCTAssertThrowsError(try Credentials.parseClaudeAccessToken(fromSecurityOutput: "not json\n")) { error in
            XCTAssertTrue(error is CredentialError)
        }
    }

    // MARK: - Formatting: paceLabel

    func testPaceLabelWithinOnePointIsEvenPace() {
        XCTAssertEqual(UsageFormat.paceLabel(0.5, windowSeconds: 604800), "ちょうど")
        XCTAssertEqual(UsageFormat.paceLabel(-0.9, windowSeconds: 18000), "ちょうど")
    }

    func testPaceLabelPositiveDifferenceIsLeadingInWeeklyWindow() {
        XCTAssertEqual(UsageFormat.paceLabel(12, windowSeconds: 604800), "使いすぎ 20時間9分")
    }

    func testPaceLabelNegativeDifferenceIsSlackInFiveHourWindow() {
        XCTAssertEqual(UsageFormat.paceLabel(-8, windowSeconds: 18000), "余裕 24分")
    }

    func testPaceLabelFallsBackToPointsWhenWindowSecondsIsZero() {
        XCTAssertEqual(UsageFormat.paceLabel(12.4, windowSeconds: 0), "使いすぎ +12pt")
    }

    // MARK: - AppState.shouldFetch

    func testShouldFetchSkipsWithinMinInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastFetchedAt = now.addingTimeInterval(-59)
        XCTAssertFalse(AppState.shouldFetch(now: now, lastFetchedAt: lastFetchedAt, retryNotBefore: nil, minInterval: 60, force: false))
    }

    func testShouldFetchAllowsAtOrAfterMinInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastFetchedAt = now.addingTimeInterval(-60)
        XCTAssertTrue(AppState.shouldFetch(now: now, lastFetchedAt: lastFetchedAt, retryNotBefore: nil, minInterval: 60, force: false))
    }

    func testShouldFetchAllowsWhenNeverFetched() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AppState.shouldFetch(now: now, lastFetchedAt: nil, retryNotBefore: nil, minInterval: 60, force: false))
    }

    func testShouldFetchSkipsWhenRetryNotBeforeIsFuture() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let retryNotBefore = now.addingTimeInterval(1)
        XCTAssertFalse(AppState.shouldFetch(now: now, lastFetchedAt: nil, retryNotBefore: retryNotBefore, minInterval: 60, force: false))
    }

    func testShouldFetchForceStillRespectsRetryNotBefore() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let retryNotBefore = now.addingTimeInterval(1)
        XCTAssertFalse(AppState.shouldFetch(now: now, lastFetchedAt: nil, retryNotBefore: retryNotBefore, minInterval: 60, force: true))
    }

    func testShouldFetchForceBypassesMinInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastFetchedAt = now.addingTimeInterval(-1)
        XCTAssertTrue(AppState.shouldFetch(now: now, lastFetchedAt: lastFetchedAt, retryNotBefore: nil, minInterval: 60, force: true))
    }

    func testShouldFetchAllowsWhenRetryNotBeforeIsPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let retryNotBefore = now.addingTimeInterval(-1)
        let lastFetchedAt = now.addingTimeInterval(-1)
        XCTAssertTrue(AppState.shouldFetch(now: now, lastFetchedAt: lastFetchedAt, retryNotBefore: retryNotBefore, minInterval: 60, force: true))
    }

    // MARK: - RetryAfterParsing

    func testRetryAfterParsingIntegerSeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = RetryAfterParsing.parse(header: "120", now: now)
        XCTAssertEqual(result, now.addingTimeInterval(120))
    }

    func testRetryAfterParsingHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 1970-01-12 13:46:41 UTC (= epoch 1_000_001, now の1秒後)
        let result = RetryAfterParsing.parse(header: "Mon, 12 Jan 1970 13:46:41 GMT", now: now)
        XCTAssertEqual(result, Date(timeIntervalSince1970: 1_000_001))
    }

    func testRetryAfterParsingMissingDefaultsTo300Seconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RetryAfterParsing.parse(header: nil, now: now), now.addingTimeInterval(300))
    }

    func testRetryAfterParsingUnparsableDefaultsTo300Seconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RetryAfterParsing.parse(header: "not-a-date", now: now), now.addingTimeInterval(300))
    }
}

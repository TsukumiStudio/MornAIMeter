import SwiftUI

@main
struct MornAIMeterApp: App {
    @StateObject private var state = AppState()
    @AppStorage("menuBarShowClaude5h") private var showClaude5h = true
    @AppStorage("menuBarShowClaudeWeekly") private var showClaudeWeekly = false
    @AppStorage("menuBarShowClaudeScoped") private var showClaudeScoped = false
    @AppStorage("menuBarShowCodexWeekly") private var showCodexWeekly = false
    @AppStorage("menuBarShowCodexAdditional") private var showCodexAdditional = false
    @AppStorage("menuBarShowAntigravityGemini") private var showAntigravityGemini = false
    @AppStorage("menuBarShowAntigravityClaudeGpt") private var showAntigravityClaudeGpt = false

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(state: state)
        } label: {
            let selections = MenuBarGaugeSelection.selected(
                claude5h: showClaude5h,
                claudeWeekly: showClaudeWeekly,
                claudeScoped: showClaudeScoped,
                codexWeekly: showCodexWeekly,
                codexAdditional: showCodexAdditional,
                antigravityGemini: showAntigravityGemini,
                antigravityClaudeGpt: showAntigravityClaudeGpt
            )
            if selections.isEmpty {
                Text("--")
            } else {
                Image(nsImage: GaugeImage.make(params: MenuBarGaugeSelection.gaugeParams(
                    selections: selections,
                    claude: state.claudeResult,
                    codex: state.codexResult,
                    antigravity: state.antigravityResult
                )))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

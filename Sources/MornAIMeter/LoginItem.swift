import ServiceManagement

enum AppLinks {
    static let repository = "https://github.com/TsukumiStudio/MornAIMeter"
}

/// SMAppService.mainApp の状態を保持し、UI から直接 SMAppService を触らせないための薄いラッパー。
final class LoginItemState: ObservableObject {
    @Published var isEnabled: Bool
    @Published var errorMessage: String?
    @Published var requiresApproval = false

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

import Foundation
import ServiceManagement
import Combine

/// Manages Launch at Login lifecycle on macOS using modern ServiceManagement API (SMAppService).
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var statusMessage: String = ""
    @Published public private(set) var requiresApproval: Bool = false
    
    private init() {
        checkStatus()
    }
    
    public func checkStatus() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            self.isEnabled = true
            self.requiresApproval = false
            self.statusMessage = "Active (Launches at login)"
        case .requiresApproval:
            self.isEnabled = false
            self.requiresApproval = true
            self.statusMessage = "Requires approval in System Settings"
        case .notRegistered:
            self.isEnabled = false
            self.requiresApproval = false
            self.statusMessage = "Disabled"
        case .notFound:
            self.isEnabled = false
            self.requiresApproval = false
            self.statusMessage = "Available when installed in Applications"
        @unknown default:
            self.isEnabled = false
            self.requiresApproval = false
            self.statusMessage = "Status unknown"
        }
    }
    
    public func setEnabled(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("[LaunchAtLogin] Error updating status: \(error.localizedDescription)")
        }
        checkStatus()
    }
    
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

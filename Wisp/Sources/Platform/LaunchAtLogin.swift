import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). The source of truth is the
/// system, not our settings file, so the toggle always reflects reality.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        Log.info("Launch at login \(enabled ? "enabled" : "disabled")", .app)
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment { AppEnvironment.shared }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let t0 = Date()
        _ = AppEnvironment.shared
        Log.info("Launch → environment in \(Int(Date().timeIntervalSince(t0) * 1000)) ms", .performance)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = environment
        if env.settings.general.showMenuBarItem && env.settings.general.hideDockIconInMenuBarMode {
            NSApp.setActivationPolicy(.accessory)
        }
        // Under XCTest the host app must not touch the real session stores.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            Log.info("Running as test host — sessions not loaded", .app)
            return
        }
        Task { @MainActor in
            if env.accounts.needsOrphanCheck {
                await env.accounts.adoptOrphanedStoresIfNeeded()
                env.sessions.reconcileActiveAccount()
            }
            env.sessions.ensureSessionsForBackgroundAccounts()
            if !env.settings.general.startHidden {
                env.window.show()
                NSApp.activateFrontmost()
            }
            Log.info("Window visible \(Int(Date().timeIntervalSince(env.launchedAt) * 1000)) ms after environment init", .performance)
            _ = await env.notifications.requestAuthorization()
        }
        #if DEBUG
        DebugHooks.installAfterLaunch(env)
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !environment.settings.general.keepRunningWhenWindowCloses
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if environment.settings.general.confirmBeforeQuit {
            let alert = NSAlert()
            alert.messageText = "Quit Wisp?"
            alert.informativeText = "You will stop receiving message notifications until Wisp is opened again."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never clear website data here — sessions must survive restarts.
        environment.settings.saveNow()
        environment.customCSS.saveNow()
        Log.info("Terminating", .app)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.badgesDidChange()
    }
}

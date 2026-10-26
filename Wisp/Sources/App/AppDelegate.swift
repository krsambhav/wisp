import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment { AppEnvironment.shared }

    private var sigtermSource: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let t0 = Date()
        // Two copies of Wisp on the same WebKit storage can corrupt WhatsApp's
        // IndexedDB (and unlink the device). Launch Services starts whichever
        // copy it has registered for the bundle id — a stale build product, say,
        // when a notification is clicked — so a second instance only hands over
        // to the first and exits, before it has touched any storage.
        let me = ProcessInfo.processInfo.processIdentifier
        if let bundleID = Bundle.main.bundleIdentifier,
           let primary = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != me }) {
            Log.warning("Another Wisp is running (pid \(primary.processIdentifier), \(primary.bundleURL?.path ?? "?")); handing over and exiting", .app)
            primary.activate()
            exit(0)
        }
        _ = AppEnvironment.shared
        // SIGTERM (e.g. `kill`, logout) → orderly quit so WebKit flushes storage.
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { AppEnvironment.shared.isQuitForced = true; NSApp.terminate(nil) }
        src.resume()
        sigtermSource = src
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
            env.updates.startAutomaticChecks()
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
        // Interrupting WhatsApp's history download can invalidate the link. Warn.
        let syncing = environment.sessions.loadedSessions.filter { $0.hasFinishedFirstLoad && $0.pageState == .loading }
        if !syncing.isEmpty && !environment.isQuitForced {
            let alert = NSAlert()
            alert.messageText = "WhatsApp is still downloading your messages"
            alert.informativeText = "Quitting now can interrupt the sync and WhatsApp may ask you to link the device again. Wait for the chat list to appear before quitting."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Quit Anyway")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        if environment.settings.general.confirmBeforeQuit && !environment.isQuitForced {
            let alert = NSAlert()
            alert.messageText = "Quit Wisp?"
            alert.informativeText = "You will stop receiving message notifications until Wisp is opened again."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        // Unload every page first so WhatsApp's pagehide handlers close IndexedDB
        // cleanly; an abrupt exit mid-transaction can corrupt its database. This is
        // done with a nested run loop: after `.terminateLater` AppKit stops draining
        // the main dispatch queue, so Swift tasks would never run.
        let live = environment.sessions.loadedSessions
        if !live.isEmpty {
            for s in live { s.beginUnloadForTermination() }
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline, live.contains(where: { !$0.isUnloadedForTermination }) {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            Log.info("Sessions unloaded for termination (\(live.filter(\.isUnloadedForTermination).count)/\(live.count))", .web)
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

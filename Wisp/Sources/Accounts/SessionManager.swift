import Foundation
import WebKit

/// Creates sessions lazily, keeps the active one in front, and (optionally)
/// keeps background accounts alive so they still deliver notifications.
@MainActor
@Observable
final class SessionManager {
    private(set) var activeAccountID: UUID?
    private(set) var sessions: [UUID: AccountSession] = [:]
    @ObservationIgnored private unowned let env: AppEnvironment

    init(environment: AppEnvironment) {
        self.env = environment
        let store = environment.accounts
        let preferred = environment.settings.window.lastActiveAccountID
        activeAccountID = store.accounts.first { $0.id == preferred }?.id ?? store.accounts.first?.id
        // Sessions are created by `ensureSessionsForBackgroundAccounts()` from the app
        // delegate, after the account list is final.
    }

    /// Re-validates the active account after the account list changed underneath us.
    func reconcileActiveAccount() {
        if activeAccountID == nil || env.accounts.account(id: activeAccountID!) == nil {
            activeAccountID = accounts.first?.id
        }
    }

    var accounts: [Account] { env.accounts.accounts }

    var activeSession: AccountSession? {
        guard let id = activeAccountID else { return nil }
        return session(for: id)
    }

    var activeAccount: Account? { activeAccountID.flatMap { env.accounts.account(id: $0) } }

    func session(for id: UUID) -> AccountSession? {
        if let s = sessions[id] { return s }
        guard let account = env.accounts.account(id: id) else { return nil }
        let s = AccountSession(account: account, environment: env)
        sessions[id] = s
        return s
    }

    var loadedSessions: [AccountSession] { sessions.values.filter(\.isWebViewCreated) }

    var totalUnread: Int { sessions.values.reduce(0) { $0 + $1.unreadCount } }

    func activate(_ id: UUID) {
        guard env.accounts.account(id: id) != nil, id != activeAccountID else { return }
        activeAccountID = id
        env.settings.window.lastActiveAccountID = id
        session(for: id)?.loadIfNeeded()
        // Sessions stay alive once created: switching back must be instant, never a reload.
        Log.info("Activated account \(id.uuidString.prefix(8))", .accounts)
    }

    func activate(index: Int) {
        guard accounts.indices.contains(index) else { return }
        activate(accounts[index].id)
    }

    /// Sessions for accounts marked "keep loaded" are created and loaded at launch
    /// so they receive messages before being opened; others are created on first
    /// activation and then kept alive for the rest of the run.
    func ensureSessionsForBackgroundAccounts() {
        for a in accounts where a.keepLoadedInBackground || a.id == activeAccountID {
            session(for: a.id)?.loadIfNeeded()
        }
        for a in accounts { Task { await session(for: a.id)?.inspectStoredData() } }
    }

    /// Drops sessions whose account no longer exists.
    private func dropSessionsForDeletedAccounts() {
        for (id, s) in sessions where env.accounts.account(id: id) == nil {
            s.tearDown(); sessions[id] = nil
        }
    }

    // MARK: Account CRUD

    @discardableResult
    func addAccount(name: String) -> Account {
        let a = env.accounts.add(name: name)
        activate(a.id)
        return a
    }

    func updateAccount(_ a: Account) {
        env.accounts.update(a)
        sessions[a.id]?.updateAccount(a)
        ensureSessionsForBackgroundAccounts()
        dropSessionsForDeletedAccounts()
    }

    func removeAccount(id: UUID) async {
        guard accounts.count > 1, let removed = env.accounts.account(id: id) else { return }
        // Order matters: make another account active and drop the account record
        // *before* suspending, so SwiftUI cannot resurrect a session for it mid-await.
        if activeAccountID == id, let next = accounts.first(where: { $0.id != id }) {
            activeAccountID = next.id
            env.settings.window.lastActiveAccountID = next.id
            session(for: next.id)?.loadIfNeeded()
        }
        env.accounts.remove(id: id)
        if let s = sessions[id] { s.tearDown(); sessions[id] = nil }
        env.notifications.withdrawAll(accountID: id)
        env.badgesDidChange()
        do { try await WKWebsiteDataStore.remove(forIdentifier: removed.dataStoreID) }
        catch { Log.warning("Could not remove data store: \(error.localizedDescription)", .accounts) }
    }

    // MARK: Fan-out

    func applyLiveStylesEverywhere() { for s in loadedSessions { s.applyLiveStyles() } }
    func applyAppearanceEverywhere() { for s in loadedSessions { s.applyAppearance() } }
    func refreshUserScriptsEverywhere() { for s in loadedSessions { s.refreshUserScripts() } }
    func reloadAll() { for s in loadedSessions { s.reload() } }
    func retryFailed() { for s in loadedSessions { s.retryNowIfFailed() } }
    func setDeveloperToolsEverywhere(_ on: Bool) { for s in loadedSessions { s.setDeveloperTools(on) } }
}

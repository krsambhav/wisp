import Foundation
import WebKit

/// Persists the list of accounts. Pure data; sessions are managed elsewhere.
@MainActor
@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []
    @ObservationIgnored private let url: URL

    init(url: URL = Paths.accountsFile) {
        self.url = url
        load()
        if accounts.isEmpty {
            // Zero-friction first launch: one account, no dialog. Not saved yet:
            // `adoptOrphanedStoresIfNeeded` first checks whether WebKit still has
            // per-account stores on disk (accounts.json lost after a bad update).
            accounts = [Account(name: "Personal", colorIndex: 3)]
            needsOrphanCheck = true
        }
    }

    /// True until the first-launch / lost-file path has checked for existing session stores.
    private(set) var needsOrphanCheck = false

    /// If accounts.json was missing but WebKit still has per-account data stores,
    /// adopt them so an update never logs anyone out. Must run before any session loads.
    func adoptOrphanedStoresIfNeeded() async {
        guard needsOrphanCheck else { return }
        needsOrphanCheck = false
        let orphans = await WKWebsiteDataStore.allDataStoreIdentifiers
        if !orphans.isEmpty {
            accounts = orphans.enumerated().map { i, id in Account(name: i == 0 ? "Personal" : "Account \(i + 1)", dataStoreID: id, colorIndex: 3 + i) }
            Log.warning("accounts.json was missing; adopted \(orphans.count) existing session store(s)", .accounts)
        }
        save()
    }

    /// v2 (2026-10): accounts connect at launch by default so every tab shows
    /// its unread count and delivers notifications without being opened first.
    private struct File: Codable { var version = 2; var accounts: [Account] }

    private var backupURL: URL { url.appendingPathExtension("bak") }

    private func load() {
        for candidate in [url, backupURL] {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            do {
                let file = try JSONDecoder.standard.decode(File.self, from: data)
                accounts = file.accounts
                if candidate == backupURL { Log.warning("accounts.json unreadable; restored from backup", .accounts) }
                if file.version < 2 {
                    for i in accounts.indices { accounts[i].keepLoadedInBackground = true }
                    save()
                }
                return
            } catch { Log.error("\(candidate.lastPathComponent) unreadable: \(error.localizedDescription)", .accounts) }
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.pretty.encode(File(accounts: accounts))
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: url, to: backupURL)
            }
            try data.write(to: url, options: .atomic)
        } catch { Log.error("Failed to save accounts: \(error.localizedDescription)", .accounts) }
    }

    func account(id: UUID) -> Account? { accounts.first { $0.id == id } }

    @discardableResult
    func add(name: String, colorIndex: Int? = nil) -> Account {
        let color = colorIndex ?? (accounts.map(\.colorIndex).max().map { $0 + 1 } ?? 0)
        let a = Account(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Account \(accounts.count + 1)" : name, colorIndex: color)
        accounts.append(a)
        save()
        Log.info("Added account \(a.id)", .accounts)
        return a
    }

    func update(_ account: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i] = account
        save()
    }

    func remove(id: UUID) {
        if let a = account(id: id), let f = a.avatarFileName {
            try? FileManager.default.removeItem(at: Paths.avatarsDirectory.appendingPathComponent(f))
        }
        accounts.removeAll { $0.id == id }
        save()
        Log.info("Removed account \(id)", .accounts)
    }

    func move(from: IndexSet, to: Int) {
        accounts.move(fromOffsets: from, toOffset: to)
        save()
    }

    /// Stores a user-picked avatar image (resized to 128px PNG).
    func setAvatar(imageData: Data?, for id: UUID) {
        guard var a = account(id: id) else { return }
        if let old = a.avatarFileName { try? FileManager.default.removeItem(at: Paths.avatarsDirectory.appendingPathComponent(old)) }
        a.avatarFileName = nil
        if let imageData {
            let name = "\(id.uuidString).png"
            do { try imageData.write(to: Paths.avatarsDirectory.appendingPathComponent(name), options: .atomic); a.avatarFileName = name }
            catch { Log.error("Failed to store avatar: \(error.localizedDescription)", .accounts) }
        }
        update(a)
    }
}

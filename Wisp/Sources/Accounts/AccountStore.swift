import Foundation

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
            // Zero-friction first launch: one account, no dialog.
            accounts = [Account(name: "Personal", colorIndex: 3)]
            save()
        }
    }

    private struct File: Codable { var version = 1; var accounts: [Account] }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do { accounts = try JSONDecoder.standard.decode(File.self, from: data).accounts }
        catch { Log.error("accounts.json unreadable: \(error.localizedDescription)", .accounts) }
    }

    private func save() {
        do { try JSONEncoder.pretty.encode(File(accounts: accounts)).write(to: url, options: .atomic) }
        catch { Log.error("Failed to save accounts: \(error.localizedDescription)", .accounts) }
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

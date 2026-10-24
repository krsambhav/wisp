import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AccountsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var newName = ""
    @State private var confirmRemove: Account?
    @State private var confirmClear: Account?
    @State private var busy: UUID?

    var body: some View {
        SettingsPage(title: "Accounts", subtitle: "Each account is a fully isolated WhatsApp Web session with its own storage, login and notifications.") {
            WGroupLabel("Accounts")
            WCard {
                ForEach(Array(env.accounts.accounts.enumerated()), id: \.element.id) { i, account in
                    if i > 0 { WDivider() }
                    AccountRow(account: account, isActive: account.id == env.sessions.activeAccountID, busy: busy == account.id,
                               onSwitch: { env.sessions.activate(account.id); env.showMainWindow() },
                               onClear: { confirmClear = account },
                               onRemove: { confirmRemove = account })
                }
            }

            WGroupLabel("Add account")
            WCard {
                HStack(spacing: 10) {
                    WTextField(placeholder: "Name, e.g. Work", text: $newName)
                    WButton(title: "Add Account", icon: "user-plus", style: .primary) {
                        env.sessions.addAccount(name: newName)
                        newName = ""
                        env.showMainWindow()
                    }
                }
                .padding(12)
                WDivider()
                Text("The new account opens WhatsApp Web with a fresh QR code. Link it from your phone under Linked Devices.")
                    .font(WispUI.caption).foregroundStyle(WispUI.mutedForeground).padding(12)
            }
        }
        .alert("Remove “\(confirmRemove?.name ?? "")”?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let a = confirmRemove { busy = a.id; Task { await env.sessions.removeAccount(id: a.id); busy = nil } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This logs the account out of Wisp and deletes all of its local data. Your WhatsApp account and messages on your phone are not affected.") }
        .alert("Log out “\(confirmClear?.name ?? "")”?", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } })) {
            Button("Log Out", role: .destructive) {
                if let a = confirmClear { busy = a.id; Task { await env.sessions.session(for: a.id)?.clearSession(); busy = nil } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Clears cookies and local storage for this account. You'll need to scan the QR code again.") }
    }
}

private struct AccountRow: View {
    @Environment(AppEnvironment.self) private var env
    let account: Account
    let isActive: Bool
    let busy: Bool
    let onSwitch: () -> Void
    let onClear: () -> Void
    let onRemove: () -> Void
    @State private var editingName: String = ""
    @State private var isEditing = false

    var body: some View {
        let session = env.sessions.sessions[account.id]
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { pickAvatar() } label: { AvatarView(account: account, size: 36).overlay(alignment: .bottomTrailing) { Circle().fill(WispUI.card).frame(width: 14, height: 14).overlay(WIcon("pencil", size: 8).foregroundStyle(WispUI.mutedForeground)) } }
                    .buttonStyle(.plain).help("Change avatar")
                VStack(alignment: .leading, spacing: 3) {
                    if isEditing {
                        WTextField(placeholder: "Name", text: $editingName).frame(width: 200)
                            .onSubmit { commitName() }
                    } else {
                        HStack(spacing: 6) {
                            Text(account.name).font(WispUI.font(13, .semibold))
                            if isActive { WBadge(text: "Active", color: WispUI.success) }
                            if let s = session, s.isWebViewCreated { WBadge(text: s.pageState.label, color: s.pageState.isFailed ? WispUI.destructive : WispUI.mutedForeground) }
                            else { WBadge(text: "Not loaded", color: WispUI.mutedForeground) }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session?.storedDataSummary ?? "").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground).padding(.trailing, 6)
                        ForEach(Array(Account.avatarPalette.enumerated()), id: \.offset) { i, c in
                            Circle().fill(c.color).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(WispUI.foreground, lineWidth: account.colorIndex % Account.avatarPalette.count == i ? 1.5 : 0))
                                .onTapGesture { var a = account; a.colorIndex = i; env.sessions.updateAccount(a) }
                        }
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if isEditing {
                    WButton(title: "Save", style: .primary, small: true) { commitName() }
                } else {
                    WButton(title: "Rename", small: true) { editingName = account.name; isEditing = true }
                    if !isActive { WButton(title: "Switch", icon: "arrow-left-right", small: true, action: onSwitch) }
                }
                WMenuButton(items: [
                    .item("Reload", icon: "refresh-cw") { env.sessions.session(for: account.id)?.reload() },
                    .item("Clear cache (keep login)", icon: "trash-2") { Task { await env.sessions.session(for: account.id)?.clearCache(); env.toasts.show(title: "Cache cleared") } },
                    .item("Log out…", icon: "log-out") { onClear() },
                    .separator,
                    .item("Remove account…", icon: "circle-x", destructive: true, disabled: env.accounts.accounts.count < 2) { onRemove() }
                ])
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            WDivider().opacity(0.5)
            HStack {
                WCheckbox(label: "Connect at launch (receive notifications before you first switch to this account)", isOn: Binding(get: { account.keepLoadedInBackground }, set: { var a = account; a.keepLoadedInBackground = $0; env.sessions.updateAccount(a) }))
                    .disabled(isActive && env.accounts.accounts.count == 1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func commitName() {
        var a = account
        let t = editingName.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { a.name = t; env.sessions.updateAccount(a) }
        isEditing = false
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        let size = NSSize(width: 128, height: 128)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let s = max(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        img.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        env.accounts.setAvatar(imageData: png, for: account.id)
        env.sessions.updateAccount(env.accounts.account(id: account.id)!)
    }
}

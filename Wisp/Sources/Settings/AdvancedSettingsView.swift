import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmReset = false
    @State private var filter: LogLevel = .info
    private let log = DiagnosticsLog.shared
    private let formatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        @Bindable var settings = env.settings
        SettingsPage(title: "Advanced", subtitle: "Web view controls, developer tools and diagnostics.") {
            WGroupLabel("Web view")
            WCard {
                WRow(title: "Reload WhatsApp", description: "Reloads the active account. Scripts and CSS are re-injected.") {
                    HStack(spacing: 8) {
                        WButton(title: "Reload", icon: "refresh-cw", small: true) { env.reloadActive() }
                        WButton(title: "Hard reload", small: true) { env.reloadActive(ignoringCache: true) }
                    }
                }
                WDivider()
                WRow(title: "Clear cache without logging out", description: "Removes HTTP and fetch caches. Cookies and app storage are kept.") {
                    WButton(title: "Clear Cache", icon: "trash-2", small: true) {
                        Task { for s in env.sessions.loadedSessions { await s.clearCache() }; env.toasts.show(title: "Cache cleared") }
                    }
                }
                WDivider()
                WRow(title: "Developer tools", description: "Adds “Inspect Element” to the right-click menu and enables Safari's Web Inspector for Wisp.") {
                    WToggle(isOn: $settings.advanced.developerToolsEnabled)
                }
                WDivider()
                WRow(title: "User-agent suffix", description: "Appended to the Safari-style user agent. Leave empty unless you know why. Applies to new sessions.") {
                    WTextField(placeholder: "", text: $settings.advanced.customUserAgentSuffix).frame(width: 220)
                }
            }

            WGroupLabel("Downloads")
            WCard {
                WRow(title: "Ask where to save each download") { WToggle(isOn: $settings.advanced.askWhereToSaveDownloads) }
                WDivider()
                WRow(title: "Reveal in Finder when done") { WToggle(isOn: $settings.advanced.revealDownloadsInFinder) }
                WDivider()
                WRow(title: "Recent downloads", description: env.downloads.items.isEmpty ? "Nothing downloaded yet." : "\(env.downloads.items.count) in this session") {
                    WButton(title: "Open Downloads", icon: "folder-open", small: true) { env.downloads.openDownloadsFolder() }
                }
                ForEach(env.downloads.items.prefix(5)) { item in
                    WDivider()
                    HStack {
                        Text(item.fileName).font(WispUI.caption).lineLimit(1)
                        Spacer()
                        switch item.state {
                        case .inProgress: ProgressView().controlSize(.mini)
                        case .finished: if let d = item.destination { WButton(title: "Show", small: true) { env.downloads.reveal(d) } }
                        case .failed(let m): Text(m).font(WispUI.caption).foregroundStyle(WispUI.destructive).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }

            WGroupLabel("Customizations")
            WCard {
                WRow(title: "Reset all customizations", description: "Default theme and layout, empty custom CSS, all scripts disabled (script files are kept). Login sessions are untouched.") {
                    WButton(title: "Reset…", icon: "rotate-ccw", style: .destructive, small: true) { confirmReset = true }
                }
                WDivider()
                if let health = env.sessions.activeSession?.selectorHealth {
                    WRow(title: "Theme hook check", description: health.missing.isEmpty ? "All \(health.total) selectors the theme relies on were found." : "Missing: \(health.missing.joined(separator: ", ")). Affected rules are skipped; WhatsApp still works.") {
                        WBadge(text: health.missing.isEmpty ? "Healthy" : "\(health.missing.count) missing", color: health.missing.isEmpty ? WispUI.success : WispUI.warning)
                    }
                } else {
                    WRow(title: "Theme hook check", description: "Runs once after WhatsApp finishes loading chats.") { WBadge(text: "Pending") }
                }
            }

            WGroupLabel("Diagnostics")
            WCard {
                HStack {
                    Picker("", selection: $filter) { ForEach(LogLevel.allCases, id: \.self) { Text($0.label.capitalized).tag($0) } }.labelsHidden().frame(width: 110)
                    Toggle("Verbose", isOn: Binding(get: { log.minimumLevel == .debug }, set: { log.minimumLevel = $0 ? .debug : .info; settings.advanced.verboseLogging = $0 })).toggleStyle(.checkbox).font(WispUI.caption)
                    Spacer()
                    Text("\(uptime) uptime · \(memoryMB) MB app process").font(WispUI.caption).foregroundStyle(WispUI.muted)
                    WButton(title: "Copy", icon: "copy", small: true) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(log.export(), forType: .string) }
                    WButton(title: "Export…", icon: "upload", small: true) { exportLog() }
                    WButton(title: "Clear", small: true) { log.clear() }
                }
                .padding(10)
                WDivider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries.filter { $0.level >= filter }.suffix(400)) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatter.string(from: e.date)).foregroundStyle(WispUI.muted)
                                Text(e.level.label).frame(width: 44, alignment: .leading).foregroundStyle(e.level == .error ? WispUI.destructive : e.level == .warning ? WispUI.warning : WispUI.muted)
                                Text(e.category).frame(width: 90, alignment: .leading).foregroundStyle(WispUI.muted).lineLimit(1)
                                Text(e.message).textSelection(.enabled)
                            }
                            .font(WispUI.mono)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 260)
            }
            Text("Logs never include message content, contact names or credentials.").font(WispUI.caption).foregroundStyle(WispUI.muted)
        }
        .alert("Reset all customizations?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { env.resetCustomizations() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var uptime: String {
        let s = Int(Date().timeIntervalSince(env.launchedAt))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private var memoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : 0
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "wisp-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? log.export().write(to: url, atomically: true, encoding: .utf8)
    }
}

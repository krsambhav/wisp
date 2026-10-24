import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScriptsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedID: UUID?
    @State private var draft: CustomScript?
    @State private var showLogs = true

    var body: some View {
        @Bindable var settings = env.settings
        HStack(spacing: 0) {
            scriptList
            Rectangle().fill(WispUI.border).frame(width: 1)
            VStack(spacing: 0) {
                if let draft {
                    editor(draft)
                } else {
                    emptyEditor
                }
                if showLogs {
                    Rectangle().fill(WispUI.border).frame(height: 1)
                    ScriptLogView().frame(height: 170)
                }
            }
        }
        .onAppear { if selectedID == nil { selectedID = env.scripts.scripts.first?.id }; syncDraft() }
        .onChange(of: selectedID) { _, _ in syncDraft() }
        .onChange(of: env.scripts.revision) { _, _ in if draft == nil || !env.scripts.scripts.contains(where: { $0.id == draft?.id }) { syncDraft() } }
    }

    private func syncDraft() {
        draft = env.scripts.scripts.first { $0.id == selectedID }
    }

    // MARK: List

    private var scriptList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scripts").font(WispUI.heading)
                Spacer()
                WIconButton(icon: "download", help: "Import .js file") { importScript() }
                WIconButton(icon: "plus", help: "New script") { let s = env.scripts.create(); selectedID = s.id }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            WDivider()
            if env.scripts.scripts.isEmpty {
                VStack(spacing: 8) {
                    WIcon("file-code", size: 24).foregroundStyle(WispUI.mutedForeground)
                    Text("No scripts yet").font(WispUI.body).foregroundStyle(WispUI.mutedForeground)
                    WButton(title: "New Script", icon: "plus", style: .primary, small: true) { let s = env.scripts.create(); selectedID = s.id }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(env.scripts.scripts) { script in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(get: { script.enabled }, set: { env.scripts.setEnabled(script.id, $0) }))
                                .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(script.name).font(WispUI.font(12.5, .medium)).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(script.world == .page ? "page" : "isolated").font(WispUI.font(10.5)).foregroundStyle(WispUI.mutedForeground)
                                    Text("·").foregroundStyle(WispUI.mutedForeground)
                                    Text(script.injectionTime == .documentStart ? "start" : "end").font(WispUI.font(10.5)).foregroundStyle(WispUI.mutedForeground)
                                }
                            }
                            Spacer()
                            if env.scripts.syntaxErrors[script.id] != nil { WIcon("triangle-alert", size: 13).foregroundStyle(WispUI.warning).help("Syntax error — not injected") }
                        }
                        .padding(.vertical, 2)
                        .tag(script.id)
                        .contextMenu {
                            Button("Delete") { env.scripts.delete(script.id); if selectedID == script.id { selectedID = env.scripts.scripts.first?.id } }
                        }
                    }
                    .onMove { env.scripts.move(from: $0, to: $1) }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            WDivider()
            VStack(alignment: .leading, spacing: 6) {
                WCheckbox(label: "Hot reload from disk", isOn: Bindable(env.settings).advanced.hotReloadScripts)
                WCheckbox(label: "Show logs", isOn: $showLogs)
                HStack {
                    WButton(title: "Open Folder", icon: "folder-open", small: true) { NSWorkspace.shared.open(env.scripts.directoryURL) }
                    WButton(title: "Disable All", icon: "power", small: true) { env.scripts.disableAll() }
                }
            }
            .padding(10)
        }
        .frame(width: 250)
        .background(WispUI.sidebar)
    }

    // MARK: Editor

    private var emptyEditor: some View {
        VStack(spacing: 8) {
            WIcon("code", size: 28).foregroundStyle(WispUI.mutedForeground)
            Text("Select a script to edit it").font(WispUI.body).foregroundStyle(WispUI.mutedForeground)
            Text("Scripts run inside WhatsApp Web. Isolated scripts see the DOM only; page-context scripts share WhatsApp's JavaScript world.")
                .font(WispUI.caption).foregroundStyle(WispUI.mutedForeground).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editor(_ script: CustomScript) -> some View {
        let binding = Binding<CustomScript>(get: { draft ?? script }, set: { draft = $0 })
        let isDirty = draft != env.scripts.scripts.first { $0.id == script.id }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                WTextField(placeholder: "Script name", text: binding.name).frame(width: 220)
                WSelect(selection: binding.injectionTime, options: ScriptInjectionTime.allCases, width: 150, small: true, label: { $0.label })
                WSelect(selection: binding.world, options: ScriptWorld.allCases, width: 190, small: true, label: { $0.label })
                Spacer()
                if isDirty { WButton(title: "Revert", small: true) { syncDraft() } }
                WButton(title: "Save", icon: "check", style: .primary, small: true) { if let d = draft { env.scripts.update(d); syncDraft() } }
                    .disabled(!isDirty).opacity(isDirty ? 1 : 0.5)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(10)
            WDivider()
            WTextField(placeholder: "Description (optional)", text: binding.summary).padding(.horizontal, 10).padding(.vertical, 8)
            WDivider()
            CodeEditorView(text: binding.source, language: .javascript)
            WDivider()
            HStack(spacing: 10) {
                if let err = CustomScript.checkSyntax(binding.wrappedValue.source) {
                    Label("\(err.message)\(err.line.map { " (line \($0))" } ?? "")", systemImage: "exclamationmark.triangle.fill").font(WispUI.caption).foregroundStyle(WispUI.warning).lineLimit(1)
                } else {
                    Label("Syntax OK", systemImage: "checkmark.circle").font(WispUI.caption).foregroundStyle(WispUI.success)
                }
                Spacer()
                Text(script.world == .page ? "Page-context scripts can break WhatsApp. Prefer isolated." : "Scripts are re-injected on every reload (⌘R).").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                WButton(title: "Save & Reload", icon: "refresh-cw", small: true) {
                    if let d = draft { env.scripts.update(d); syncDraft() }
                    env.sessions.reloadAll()
                }
                WButton(title: "Delete", icon: "trash-2", style: .destructive, small: true) {
                    env.scripts.delete(script.id); selectedID = env.scripts.scripts.first?.id
                }
            }
            .padding(10)
        }
    }

    private func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.javaScript, UTType(filenameExtension: "js") ?? .plainText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { let s = try env.scripts.importScript(from: url); selectedID = s.id }
            catch { env.toasts.show(title: "Import failed: \(error.localizedDescription)") }
        }
    }
}

struct ScriptLogView: View {
    @Environment(AppEnvironment.self) private var env
    private let log = DiagnosticsLog.shared
    private let formatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    private var entries: [LogEntry] {
        log.entries.filter { $0.category.hasPrefix("script:") || $0.category == LogCategory.scripts.rawValue || $0.category == LogCategory.injection.rawValue }.suffix(300)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Execution log").font(WispUI.heading)
                Spacer()
                WButton(title: "Clear", small: true) { log.clear() }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            WDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatter.string(from: e.date)).foregroundStyle(WispUI.mutedForeground)
                                Text(e.level.label).foregroundStyle(color(for: e.level)).frame(width: 44, alignment: .leading)
                                Text(e.category.replacingOccurrences(of: "script:", with: "")).foregroundStyle(WispUI.mutedForeground).frame(width: 110, alignment: .leading).lineLimit(1)
                                Text(e.message).textSelection(.enabled)
                            }
                            .font(WispUI.mono)
                            .id(e.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: entries.count) { _, _ in if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(WispUI.card)
    }

    private func color(for level: LogLevel) -> Color {
        switch level { case .debug: WispUI.mutedForeground; case .info: WispUI.foreground; case .warning: WispUI.warning; case .error: WispUI.destructive }
    }
}

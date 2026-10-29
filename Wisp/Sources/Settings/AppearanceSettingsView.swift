import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @State private var cssDraft: String = ""
    @State private var presetName = "My preset"
    @State private var includeScriptsInPreset = false
    @State private var ioMessage: String?

    private let accentPresets: [(String, HexColor?)] = [
        ("Theme", nil), ("Green", HexColor("#1DAA61")), ("Blue", HexColor("#2563EB")), ("Indigo", HexColor("#6366F1")),
        ("Violet", HexColor("#8B5CF6")), ("Rose", HexColor("#E11D48")), ("Orange", HexColor("#F97316")), ("Teal", HexColor("#0D9488")), ("Graphite", HexColor("#27272A"))
    ]

    var body: some View {
        @Bindable var settings = env.settings
        @Bindable var customCSS = env.customCSS
        SettingsPage(title: "Appearance", subtitle: "Themes, accent, typography and your own CSS. Changes apply live — no reload.") {
            WGroupLabel("Theme")
            HStack(spacing: 12) {
                ForEach(ThemeCatalog.all) { theme in
                    ThemeCard(theme: theme, selected: settings.appearance.themeID == theme.id, dark: colorScheme == .dark) {
                        settings.appearance.themeID = theme.id
                    }
                }
            }
            WCard {
                WRow(title: "Mode", description: env.currentTheme.preferredMode != nil ? "\(env.currentTheme.name) is a \(env.currentTheme.preferredMode!.label.lowercased()) theme and sets this itself." : "Forces WhatsApp's light or dark scheme. WhatsApp's own theme setting must be “System default” for this to apply.") {
                    WSegmented(selection: $settings.appearance.mode, options: AppearanceMode.allCases, label: { $0.label })
                        .disabled(env.currentTheme.preferredMode != nil)
                }
            }

            WGroupLabel("Accent")
            WCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(accentPresets, id: \.0) { name, color in
                            AccentSwatch(name: name, color: color?.color ?? env.currentTheme.palette(for: colorScheme == .dark).accent.color,
                                         isTheme: color == nil, selected: settings.appearance.accentOverride == color) {
                                settings.appearance.accentOverride = color
                            }
                        }
                        ColorPicker("Custom", selection: Binding(
                            get: { settings.appearance.accentOverride?.color ?? env.currentTheme.palette(for: colorScheme == .dark).accent.color },
                            set: { settings.appearance.accentOverride = HexColor(nsColor: NSColor($0)) }), supportsOpacity: false)
                        .labelsHidden()
                    }
                    Text("Accent drives buttons, unread badges, read receipts and focus rings.").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                }
                .padding(14)
                WDivider()
                WRow(title: "Tint outgoing bubbles with accent", description: "Off makes your messages a neutral surface color.") {
                    WToggle(isOn: $settings.appearance.tintOutgoingBubbles)
                }
            }

            WGroupLabel("Messages")
            WCard {
                WRow(title: "Copy button on hover", description: "A Copy button next to React when you hover a message. Copies the text, emoji included.") {
                    WToggle(isOn: $settings.appearance.copyButtonEnabled)
                }
                WDivider()
                WRow(title: "Download button on hover", description: "A Download button on photos, videos, documents and stickers. Saves through WhatsApp's own download, so files land where they always do.") {
                    WToggle(isOn: $settings.appearance.downloadButtonEnabled)
                }
                WDivider()
                WRow(title: "Copy file button on hover", description: "Copies the photo, video, document or sticker itself to the clipboard, ready to paste into Finder, Mail or another chat.") {
                    WToggle(isOn: $settings.appearance.copyFileButtonEnabled)
                }
            }

            WGroupLabel("Typography & layout")
            WCard {
                WRow(title: "Font") {
                    WSelect(selection: $settings.appearance.font, options: FontChoice.allCases, width: 220, label: { $0.label })
                }
                WDivider()
                WRow(title: "Interface scale", description: "\(Int(settings.appearance.interfaceScale * 100))% — also ⌘+ / ⌘−") {
                    Slider(value: $settings.appearance.interfaceScale, in: 0.8...1.4, step: 0.05).frame(width: 200)
                }
                WDivider()
                WRow(title: "Message text size", description: "\(Int(settings.appearance.messageFontScale * 100))% of WhatsApp's default") {
                    Slider(value: $settings.appearance.messageFontScale, in: 0.85...1.4, step: 0.05).frame(width: 200)
                }
                WDivider()
                WRow(title: "Density", description: "Compact tightens message spacing, headers and the composer. Chat list rows are sized by WhatsApp.") {
                    WSegmented(selection: $settings.appearance.density, options: Density.allCases, label: { $0.label })
                }
                WDivider()
                WRow(title: "Rounded message bubbles", description: settings.appearance.roundedBubbles ? "Radius \(Int(settings.appearance.bubbleRadius)) pt" : "WhatsApp's default bubble shape") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.appearance.bubbleRadius, in: 6...24, step: 1).frame(width: 140).disabled(!settings.appearance.roundedBubbles)
                        WToggle(isOn: $settings.appearance.roundedBubbles)
                    }
                }
                WDivider()
                WRow(title: "Sidebar width", description: settings.appearance.sidebarWidth.map { "\(Int($0)) pt" } ?? "WhatsApp's responsive default") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { settings.appearance.sidebarWidth ?? 400 }, set: { settings.appearance.sidebarWidth = $0 }), in: 300...560, step: 10)
                            .frame(width: 140).disabled(settings.appearance.sidebarWidth == nil)
                        WToggle(isOn: Binding(get: { settings.appearance.sidebarWidth != nil }, set: { settings.appearance.sidebarWidth = $0 ? 400 : nil }))
                    }
                }
            }

            WGroupLabel("Custom CSS")
            WCard {
                WRow(title: "Enable custom CSS", description: "Injected after the theme. Use --wisp-* variables to stay in sync with the theme.") {
                    HStack(spacing: 10) {
                        WCheckbox(label: "Live preview", isOn: $settings.appearance.livePreview)
                        WToggle(isOn: $settings.appearance.customCSSEnabled)
                    }
                }
                WDivider()
                CodeEditorView(text: $customCSS.css, language: .css)
                    .frame(height: 220)
                WDivider()
                HStack {
                    if let err = customCSS.validationError {
                        Label(err, systemImage: "exclamationmark.triangle.fill").font(WispUI.caption).foregroundStyle(WispUI.warning)
                    } else {
                        Text("\(customCSS.css.count) characters").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                    }
                    Spacer()
                    if !settings.appearance.livePreview {
                        WButton(title: "Apply", icon: "check", style: .primary, small: true) { env.sessions.applyLiveStylesEverywhere() }
                    }
                    WButton(title: "Clear", icon: "trash-2", small: true) { customCSS.css = "" }
                }
                .padding(10)
            }

            WGroupLabel("Presets")
            WCard {
                WRow(title: "Export preset", description: "Saves theme, accent, layout and custom CSS to a JSON file.") {
                    HStack(spacing: 8) {
                        WCheckbox(label: "Include scripts", isOn: $includeScriptsInPreset)
                        WButton(title: "Export…", icon: "upload", small: true) { exportPreset() }
                    }
                }
                WDivider()
                WRow(title: "Import preset", description: ioMessage ?? "Imported scripts start disabled.") {
                    WButton(title: "Import…", icon: "download", small: true) { importPreset() }
                }
                WDivider()
                WRow(title: "Reset appearance", description: "Back to the Default theme and defaults. Custom CSS and scripts are kept.") {
                    WButton(title: "Reset", icon: "rotate-ccw", small: true) { settings.resetAppearance() }
                }
            }
        }
    }

    private func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Wisp Preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = env.exportPreset(name: url.deletingPathExtension().lastPathComponent, includeScripts: includeScriptsInPreset)
            try PresetIO.encode(preset).write(to: url, options: .atomic)
            ioMessage = "Exported to \(url.lastPathComponent)"
        } catch { ioMessage = "Export failed: \(error.localizedDescription)" }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = try PresetIO.decode(Data(contentsOf: url))
            env.applyPreset(preset, includeScripts: includeScriptsInPreset)
            ioMessage = "Imported “\(preset.name)”"
        } catch { ioMessage = "Import failed: \(error.localizedDescription)" }
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let selected: Bool
    let dark: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let p = theme.palette(for: theme.preferredMode == .dark ? true : (theme.preferredMode == .light ? false : dark))
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Miniature of the layout
                HStack(spacing: 3) {
                    VStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 1 ? p.surfaceEmphasized.color : p.surface.color)
                                .overlay(alignment: .leading) { Circle().fill(p.textSecondary.color.opacity(0.5)).frame(width: 6, height: 6).padding(.leading, 3) }
                        }
                    }
                    .frame(width: 48)
                    .padding(3).background(p.surface.color)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(p.bubbleIncoming.color).frame(width: 46, height: 10)
                        HStack { Spacer(); RoundedRectangle(cornerRadius: 3).fill(p.bubbleOutgoing.color).frame(width: 52, height: 10) }
                        RoundedRectangle(cornerRadius: 3).fill(p.bubbleIncoming.color).frame(width: 34, height: 10)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3).fill(p.composer.color).frame(height: 9).overlay(alignment: .trailing) { Circle().fill(p.accent.color).frame(width: 7, height: 7).padding(.trailing, 2) }
                    }
                    .padding(5).frame(maxWidth: .infinity).background(p.chatBackground.color)
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(p.divider.color, lineWidth: 1))

                HStack {
                    Text(theme.name).font(WispUI.font(13, .semibold)).foregroundStyle(WispUI.foreground)
                    Spacer()
                    if selected { WIcon("circle-check", size: 14).foregroundStyle(WispUI.foreground) }
                }
                Text(theme.summary).font(WispUI.caption).foregroundStyle(WispUI.mutedForeground).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WispUI.card)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous).stroke(selected ? WispUI.foreground.opacity(0.7) : (hovering ? WispUI.borderStrong : WispUI.border), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AccentSwatch: View {
    let name: String
    let color: Color
    let isTheme: Bool
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 22, height: 22)
                if isTheme { WIcon("sparkles", size: 11).foregroundStyle(.white) }
                Circle().stroke(selected ? WispUI.foreground : .clear, lineWidth: 2).frame(width: 28, height: 28)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

import SwiftUI

// MARK: - Icon

struct WIcon: View {
    let name: String
    var size: CGFloat = 16
    init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        Image("lucide.\(name)")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Card (shadcn Card: border, rounded-lg, bg-card)

struct WCard<Content: View>: View {
    var title: String? = nil
    var description: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title { Text(title).font(WispUI.heading).foregroundStyle(WispUI.foreground) }
                    if let description { Text(description).font(WispUI.caption).foregroundStyle(WispUI.mutedForeground) }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                WDivider()
            }
            content
        }
        .background(WispUI.card)
        .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous).stroke(WispUI.border, lineWidth: 1))
    }
}

struct WDivider: View {
    var body: some View { Rectangle().fill(WispUI.border).frame(height: 1) }
}

/// Label + optional description on the left, control on the right (shadcn "form row").
struct WRow<Control: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(WispUI.bodyMedium).foregroundStyle(WispUI.foreground)
                if let description {
                    Text(description).font(WispUI.caption).foregroundStyle(WispUI.mutedForeground).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct WSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(WispUI.title).foregroundStyle(WispUI.foreground)
            if let subtitle { Text(subtitle).font(WispUI.body).foregroundStyle(WispUI.mutedForeground) }
        }
        .padding(.bottom, 8)
    }
}

struct WGroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(WispUI.font(13, .semibold))
            .foregroundStyle(WispUI.foreground)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }
}

// MARK: - Buttons (shadcn variants: default, secondary, outline, ghost, destructive)

enum WButtonStyle { case primary, secondary, outline, ghost, destructive }

struct WButton: View {
    let title: String
    var icon: String? = nil
    var style: WButtonStyle = .outline
    var small: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { WIcon(icon, size: small ? 13 : 14) }
                Text(title).font(WispUI.font(small ? 12.5 : 13.5, .medium))
            }
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 28 : 34)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous).stroke(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch style {
        case .primary: WispUI.primaryForeground
        case .destructive: WispUI.destructiveForeground
        case .secondary: WispUI.secondaryForeground
        case .outline, .ghost: WispUI.foreground
        }
    }
    private var background: Color {
        switch style {
        case .primary: WispUI.primary.opacity(hovering ? 0.9 : 1)
        case .destructive: WispUI.destructive.opacity(hovering ? 0.9 : 1)
        case .secondary: WispUI.secondary.opacity(hovering ? 0.8 : 1)
        case .outline: hovering ? WispUI.accent : WispUI.background
        case .ghost: hovering ? WispUI.accent : .clear
        }
    }
    private var border: Color { style == .outline ? WispUI.input : .clear }
}

/// Square icon button (shadcn `variant="ghost" size="icon"`).
struct WIconButton: View {
    let icon: String
    var help: String = ""
    var tint: Color? = nil
    var size: CGFloat = 28
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            WIcon(icon, size: 15)
                .foregroundStyle(tint ?? WispUI.foreground.opacity(hovering ? 1 : 0.8))
                .frame(width: size, height: size)
                .background(hovering ? WispUI.accent.opacity(0.9) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Switch & Checkbox (shadcn)

struct WToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? WispUI.primary : WispUI.input).frame(width: 36, height: 20)
                Circle().fill(isOn ? WispUI.primaryForeground : WispUI.background)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

struct WCheckbox: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(isOn ? WispUI.primary : WispUI.background).frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(isOn ? WispUI.primary : WispUI.ring.opacity(0.5), lineWidth: 1))
                    if isOn { WIcon("check", size: 11).foregroundStyle(WispUI.primaryForeground) }
                }
                Text(label).font(WispUI.caption).foregroundStyle(WispUI.foreground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tabs (shadcn Tabs list)

struct WSegmented<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let selected = opt == selection
                Button { selection = opt } label: {
                    Text(label(opt))
                        .font(WispUI.font(12.5, .medium))
                        .padding(.horizontal, 12).frame(height: 26)
                        .foregroundStyle(selected ? WispUI.foreground : WispUI.mutedForeground)
                        .background(selected ? WispUI.background : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(WispUI.mutedForeground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Badge (shadcn Badge: secondary / outline)

struct WBadge: View {
    let text: String
    var color: Color = WispUI.mutedForeground
    var body: some View {
        Text(text)
            .font(WispUI.font(11, .semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Input (shadcn Input)

struct WTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(WispUI.body)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(WispUI.background)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous).stroke(focused ? WispUI.ring : WispUI.input, lineWidth: focused ? 1.5 : 1))
    }
}

// MARK: - Unread badge pill

struct UnreadPill: View {
    let count: Int
    let color: Color
    let textColor: Color
    var body: some View {
        Text(count > 99 ? "99+" : String(count))
            .font(WispUI.font(9.5, .bold))
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .foregroundStyle(textColor)
            .background(color)
            .clipShape(Capsule())
    }
}

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

// MARK: - Card & rows

struct WCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(WispUI.card)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous).stroke(WispUI.border, lineWidth: 1))
    }
}

struct WDivider: View {
    var body: some View { Rectangle().fill(WispUI.border).frame(height: 1) }
}

/// Label + optional description on the left, control on the right.
struct WRow<Control: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WispUI.body).foregroundStyle(WispUI.foreground)
                if let description {
                    Text(description).font(WispUI.caption).foregroundStyle(WispUI.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct WSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(WispUI.title).foregroundStyle(WispUI.foreground)
            if let subtitle { Text(subtitle).font(WispUI.body).foregroundStyle(WispUI.muted) }
        }
        .padding(.bottom, 6)
    }
}

struct WGroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(WispUI.muted)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

// MARK: - Buttons

enum WButtonStyle { case primary, secondary, ghost, destructive }

struct WButton: View {
    let title: String
    var icon: String? = nil
    var style: WButtonStyle = .secondary
    var small: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { WIcon(icon, size: small ? 13 : 14) }
                Text(title).font(.system(size: small ? 12 : 13, weight: .medium))
            }
            .padding(.horizontal, small ? 10 : 12)
            .frame(height: small ? 26 : 30)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous).stroke(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch style {
        case .primary: WispUI.primaryForeground
        case .destructive: .white
        case .secondary, .ghost: WispUI.foreground
        }
    }
    private var background: Color {
        switch style {
        case .primary: WispUI.primary.opacity(hovering ? 0.88 : 1)
        case .destructive: WispUI.destructive.opacity(hovering ? 0.88 : 1)
        case .secondary: hovering ? WispUI.hover : WispUI.card
        case .ghost: hovering ? WispUI.hover : .clear
        }
    }
    private var border: Color {
        switch style {
        case .secondary: WispUI.border
        default: .clear
        }
    }
}

/// Square icon button used in the header bar.
struct WIconButton: View {
    let icon: String
    var help: String = ""
    var tint: Color? = nil
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            WIcon(icon, size: 15)
                .foregroundStyle(tint ?? WispUI.foreground.opacity(hovering ? 1 : 0.78))
                .frame(width: size, height: size)
                .background(hovering ? WispUI.hover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Toggle / segmented

struct WToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
    }
}

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
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .padding(.horizontal, 10).frame(height: 24)
                        .foregroundStyle(selected ? WispUI.foreground : WispUI.muted)
                        .background(selected ? WispUI.card : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(WispUI.hover)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Badge

struct WBadge: View {
    let text: String
    var color: Color = WispUI.muted
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Text field

struct WTextField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(WispUI.body)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(WispUI.card)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous).stroke(WispUI.borderStrong, lineWidth: 1))
    }
}

// MARK: - Unread badge pill

struct UnreadPill: View {
    let count: Int
    let color: Color
    let textColor: Color
    var body: some View {
        Text(count > 99 ? "99+" : String(count))
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .foregroundStyle(textColor)
            .background(color)
            .clipShape(Capsule())
    }
}

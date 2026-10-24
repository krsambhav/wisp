import AppKit
import SwiftUI

// shadcn-style DropdownMenu / Select, rendered in a borderless child panel so
// there is no NSMenu chrome and no popover arrow.

struct WMenuItem: Identifiable {
    enum Kind { case item, separator, label }
    let id = UUID()
    var kind: Kind = .item
    var title: String = ""
    var icon: String? = nil
    var destructive = false
    var disabled = false
    var checked = false
    var action: (@MainActor () -> Void)? = nil

    static func item(_ title: String, icon: String? = nil, destructive: Bool = false, disabled: Bool = false, checked: Bool = false, action: @escaping @MainActor () -> Void) -> WMenuItem {
        WMenuItem(kind: .item, title: title, icon: icon, destructive: destructive, disabled: disabled, checked: checked, action: action)
    }
    static var separator: WMenuItem { WMenuItem(kind: .separator) }
    static func label(_ title: String) -> WMenuItem { WMenuItem(kind: .label, title: title) }
}

/// Trigger + menu. `label` is the trigger content; the menu opens below it.
struct WDropdown<Label: View>: View {
    let items: [WMenuItem]
    var width: CGFloat = 200
    var alignTrailing = true
    @ViewBuilder var label: Label
    @State private var anchor = AnchorBox()

    var body: some View {
        Button {
            guard let view = anchor.view, let window = view.window else { return }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            MenuPanelController.shared.show(items: items, anchorScreenRect: rect, width: width, alignTrailing: alignTrailing, parent: window)
        } label: { label }
        .buttonStyle(.plain)
        .background(AnchorView(box: anchor))
    }
}

/// Icon-only trigger (ellipsis) matching `WIconButton`.
struct WMenuButton: View {
    let items: [WMenuItem]
    var icon: String = "ellipsis"
    var width: CGFloat = 220
    @State private var hovering = false
    var body: some View {
        WDropdown(items: items, width: width) {
            WIcon(icon, size: 15)
                .foregroundStyle(WispUI.foreground.opacity(hovering ? 1 : 0.8))
                .frame(width: 28, height: 28)
                .background(hovering ? WispUI.accent : .clear)
                .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
                .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
    }
}

/// shadcn Select: bordered trigger with the current value and a chevron.
struct WSelect<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    var width: CGFloat = 200
    var small = false
    let label: (T) -> String
    @State private var hovering = false

    var body: some View {
        WDropdown(items: options.map { opt in
            .item(label(opt), checked: opt == selection) { selection = opt }
        }, width: width, alignTrailing: false) {
            HStack(spacing: 8) {
                Text(label(selection)).font(WispUI.font(small ? 12.5 : 13.5)).foregroundStyle(WispUI.foreground).lineLimit(1)
                Spacer(minLength: 4)
                WIcon("chevron-down", size: 13).foregroundStyle(WispUI.mutedForeground)
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: small ? 28 : 34)
            .background(hovering ? WispUI.accent.opacity(0.6) : WispUI.background)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous).stroke(WispUI.input, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Anchor plumbing

@MainActor final class AnchorBox { weak var view: NSView? }

private struct AnchorView: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}

// MARK: - Panel

@MainActor
final class MenuPanelController {
    static let shared = MenuPanelController()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private weak var parent: NSWindow?

    func show(items: [WMenuItem], anchorScreenRect: NSRect, width: CGFloat, alignTrailing: Bool, parent: NSWindow) {
        dismiss()
        let content = MenuContentView(items: items, width: width) { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = hosting

        var x = alignTrailing ? anchorScreenRect.maxX - size.width : anchorScreenRect.minX
        var y = anchorScreenRect.minY - size.height - 4
        if let screen = parent.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            if y < vf.minY { y = anchorScreenRect.maxY + 4 }
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel
        self.parent = parent

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel { self.dismiss() }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismiss() } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        } as Any)
    }

    func dismiss() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        if let panel {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
    }
}

private struct MenuContentView: View {
    let items: [WMenuItem]
    let width: CGFloat
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items) { item in
                switch item.kind {
                case .separator: WDivider().padding(.vertical, 4).padding(.horizontal, -4)
                case .label: Text(item.title).font(WispUI.font(12, .semibold)).foregroundStyle(WispUI.mutedForeground).padding(.horizontal, 8).padding(.vertical, 6)
                case .item: MenuRow(item: item) { dismiss(); item.action?() }
                }
            }
        }
        .padding(4)
        .frame(width: width)
        .background(WispUI.popover)
        .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous).stroke(WispUI.border, lineWidth: 1))
    }
}

private struct MenuRow: View {
    let item: WMenuItem
    let select: @MainActor () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                if let icon = item.icon { WIcon(icon, size: 14).foregroundStyle(color.opacity(0.85)) }
                Text(item.title).font(WispUI.font(13)).foregroundStyle(color).lineLimit(1)
                Spacer(minLength: 8)
                if item.checked { WIcon("check", size: 13).foregroundStyle(WispUI.foreground) }
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(hovering && !item.disabled ? (item.destructive ? WispUI.destructive.opacity(0.1) : WispUI.accent) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusSM, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.disabled)
        .opacity(item.disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
    private var color: Color { item.destructive ? WispUI.destructive : WispUI.foreground }
}

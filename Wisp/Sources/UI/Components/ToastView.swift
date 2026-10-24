import SwiftUI

struct ToastStack: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 8) {
            ForEach(env.toasts.toasts) { toast in
                HStack(spacing: 12) {
                    Text(toast.title).font(.system(size: 12.5, weight: .medium)).lineLimit(2)
                    if let actionTitle = toast.actionTitle {
                        Button(actionTitle) { toast.action?(); env.toasts.dismiss(toast.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Button { env.toasts.dismiss(toast.id) } label: { WIcon("x", size: 12).foregroundStyle(WispUI.mutedForeground) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(WispUI.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: WispUI.radiusLG, style: .continuous).stroke(WispUI.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.spring(duration: 0.3), value: env.toasts.toasts)
    }
}

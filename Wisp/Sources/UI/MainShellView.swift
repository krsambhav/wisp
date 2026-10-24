import SwiftUI

/// Header + persistent web view + overlays. The web view itself is owned by
/// the session; this view only hosts it.
struct MainShellView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = env.shellPalette(systemIsDark: colorScheme == .dark)
        VStack(spacing: 0) {
            HeaderBar(palette: palette)
            ZStack {
                palette.shellBackground.color
                if let session = env.sessions.activeSession {
                    WebViewContainer(webView: session.webView)
                        .id(session.account.id)
                        .onAppear { session.loadIfNeeded() }
                    SessionOverlays(session: session, palette: palette)
                } else {
                    NoAccountsView()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { ToastStack() }
        .ignoresSafeArea()
    }
}

private struct SessionOverlays: View {
    let session: AccountSession
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            if case .failed(let message) = session.pageState {
                OfflineOverlay(message: message, isOnline: env.network.isOnline) { session.retryNowIfFailed() }
            } else if !session.hasFinishedFirstLoad {
                LoadingOverlay(palette: palette)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.hasFinishedFirstLoad)
    }
}

private struct LoadingOverlay: View {
    let palette: ThemePalette
    var body: some View {
        ZStack {
            palette.shellBackground.color
            VStack(spacing: 14) {
                ProgressView().controlSize(.small)
                Text("Connecting to WhatsApp…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.shellForeground.color.opacity(0.6))
            }
        }
    }
}

private struct OfflineOverlay: View {
    let message: String
    let isOnline: Bool
    let retry: () -> Void

    var body: some View {
        ZStack {
            WispUI.background
            VStack(spacing: 10) {
                WIcon("triangle-alert", size: 28).foregroundStyle(WispUI.warning)
                Text(isOnline ? "Couldn't reach WhatsApp" : "You're offline")
                    .font(.system(size: 16, weight: .semibold))
                Text(isOnline ? message : "Wisp will reconnect automatically when the network is back.")
                    .font(WispUI.body).foregroundStyle(WispUI.mutedForeground)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                WButton(title: "Try Again", icon: "refresh-cw", style: .primary, action: retry).padding(.top, 6)
            }
            .padding(32)
        }
    }
}

private struct NoAccountsView: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        VStack(spacing: 12) {
            Text("No accounts").font(.system(size: 16, weight: .semibold))
            WButton(title: "Add Account", icon: "plus", style: .primary) { env.openSettings(.accounts) }
        }
    }
}

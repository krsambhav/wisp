import AppKit
import SwiftUI

/// Click, then press a combination. Esc cancels, ⌫ clears.
struct HotKeyRecorderView: View {
    @Binding var hotKey: HotKey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                Text(recording ? "Press keys…" : hotKey.displayString)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? WispUI.muted : WispUI.foreground)
                if !recording { WIcon("keyboard", size: 12).foregroundStyle(WispUI.muted) }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(WispUI.card)
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous).stroke(recording ? Color.accentColor : WispUI.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // esc
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
            guard !mods.isEmpty, !mods.isSubset(of: [.shift]) else { return nil } // require a real modifier
            hotKey = HotKey(keyCode: event.keyCode, modifiers: mods.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

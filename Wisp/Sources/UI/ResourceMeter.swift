import AppKit
import SwiftUI

/// Header meter: a two-minute CPU sparkline beside the live CPU and memory
/// totals for Wisp and its WebKit helpers. Click for the per-process breakdown.
struct ResourceMeter: View {
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env
    @State private var hovering = false
    @State private var showingDetails = false

    var body: some View {
        let fg = palette.shellForeground.color
        let monitor = env.resources
        let lit = hovering || showingDetails
        Button { showingDetails.toggle() } label: {
            HStack(spacing: 8) {
                Sparkline(values: monitor.history, color: fg.opacity(lit ? 0.85 : 0.5))
                    .frame(width: 32, height: 12)
                if let s = monitor.sample {
                    HStack(spacing: 5) {
                        Text(ResourceFormat.cpu(s.cpu)).frame(minWidth: 30, alignment: .trailing)
                        Text("·").opacity(0.5)
                        Text(ResourceFormat.memory(s.memory))
                    }
                } else {
                    Text("Measuring…").opacity(0.7)
                }
            }
            .font(WispUI.font(11, .medium))
            .monospacedDigit()
            .foregroundStyle(fg.opacity(lit ? 0.92 : 0.55))
            .padding(.leading, 9).padding(.trailing, 10)
            .frame(height: 26)
            .background(lit ? fg.opacity(0.06) : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
        .help("CPU and memory used by Wisp, including its WebKit helpers. Click for details.")
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            ResourceDetails()
                .presentationBackground(WispUI.cardElevated)
        }
        .task { await monitor.run() }
    }
}

// MARK: - Details popover

private struct ResourceDetails: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let monitor = env.resources
        let sample = monitor.sample
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wisp resources").font(WispUI.heading).foregroundStyle(WispUI.foreground)
                Text("The app plus the WebKit helpers macOS runs for it, grouped the way Activity Monitor does.")
                    .font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)

            HStack(spacing: 10) {
                StatTile(label: "CPU",
                         value: sample.map { ResourceFormat.cpu($0.cpu) } ?? "—",
                         detail: "peak \(ResourceFormat.cpu(monitor.peakCPU)) · 2 min") {
                    Sparkline(values: monitor.history, color: WispUI.foreground.opacity(0.75), filled: true)
                        .frame(height: 26)
                }
                StatTile(label: "Memory",
                         value: sample.map { ResourceFormat.memory($0.memory) } ?? "—",
                         detail: sample.map { "\($0.processCount) process\($0.processCount == 1 ? "" : "es")\($0.exact ? "" : " · resident") " } ?? "") {
                    MemoryBar(groups: sample?.groups ?? [], total: sample?.memory ?? 0)
                        .frame(height: 26)
                }
            }
            .padding(.horizontal, 16)

            if let sample, !sample.groups.isEmpty {
                WDivider().padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(sample.groups) { group in
                        HStack(spacing: 8) {
                            Circle().fill(ResourceFormat.tint(for: group.name)).frame(width: 6, height: 6)
                            Text(group.name).font(WispUI.font(12.5, .medium)).foregroundStyle(WispUI.foreground)
                            if group.count > 1 {
                                Text("×\(group.count)").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                            }
                            Spacer(minLength: 8)
                            Text(ResourceFormat.cpu(group.cpu))
                                .frame(minWidth: 44, alignment: .trailing)
                            Text(ResourceFormat.memory(group.memory))
                                .frame(minWidth: 62, alignment: .trailing)
                        }
                        .font(WispUI.font(12)).monospacedDigit()
                        .foregroundStyle(WispUI.mutedForeground)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
            } else {
                Spacer().frame(height: 14)
            }

            WDivider()
            HStack {
                WButton(title: "Activity Monitor", icon: "gauge", style: .ghost, small: true) { monitor.openActivityMonitor() }
                Spacer()
                WButton(title: "Hide", style: .ghost, small: true) {
                    monitor.showsInHeader = false
                    env.toasts.show(title: "Resource meter hidden. Turn it back on in Settings › General.", actionTitle: "Undo") {
                        monitor.showsInHeader = true
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

private struct StatTile<Graphic: View>: View {
    let label: String
    let value: String
    let detail: String
    @ViewBuilder var graphic: Graphic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(WispUI.font(10, .semibold)).tracking(0.6)
                .foregroundStyle(WispUI.mutedForeground)
            Text(value)
                .font(WispUI.font(20, .semibold)).monospacedDigit()
                .foregroundStyle(WispUI.foreground)
            graphic
            Text(detail)
                .font(WispUI.font(10.5)).monospacedDigit()
                .foregroundStyle(WispUI.mutedForeground)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WispUI.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
    }
}

/// Stacked bar: each process group's share of the footprint.
private struct MemoryBar: View {
    let groups: [ResourceMonitor.ProcessGroup]
    let total: UInt64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(groups) { g in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ResourceFormat.tint(for: g.name))
                        .frame(width: max(2, geo.size.width * CGFloat(total == 0 ? 0 : Double(g.memory) / Double(total)) - 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Sparkline

/// Lightweight line chart of recent CPU samples. Scales to the window's peak
/// with a floor so an idle app draws a calm low line rather than noise.
struct Sparkline: View {
    let values: [Double]
    var color: Color
    var filled: Bool = false
    var floor: Double = 25

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if filled, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                if pts.count > 1 {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height - 0.75))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 0.75))
                    }
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                if let last = pts.last {
                    Circle().fill(color).frame(width: 3, height: 3).position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let ceiling = max(floor, values.max() ?? 0)
        let n = ResourceMonitor.historyLength
        let step = size.width / CGFloat(n - 1)
        let x0 = size.width - step * CGFloat(values.count - 1)   // grow in from the right
        let inset: CGFloat = 1.5
        return values.enumerated().map { i, v in
            CGPoint(x: x0 + step * CGFloat(i),
                    y: inset + (size.height - inset * 2) * CGFloat(1 - min(v, ceiling) / ceiling))
        }
    }
}

// MARK: - Formatting

enum ResourceFormat {
    static func cpu(_ percent: Double) -> String {
        percent < 10 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB]
        return f
    }()

    static func memory(_ bytes: UInt64) -> String {
        memoryFormatter.string(fromByteCount: Int64(bytes))
    }

    static func tint(for group: String) -> Color {
        switch group {
        case "Wisp": WispUI.foreground
        case "Web content": WispUI.success
        case "Networking": WispUI.warning
        case "Graphics": WispUI.adaptive("#7C3AED", "#A78BFA")
        default: WispUI.mutedForeground
        }
    }
}

import SwiftUI
import GamemoteCore

/// The controller's console: a status bar (link, signal, round-trip time) over the message log,
/// and a legend of what each letter does on the gadget.
struct ConsoleScreen: View {
    let model: AppModel
    var legend: [(letter: String, meaning: String?)]
    /// Text scale: the sideways screen is small, the upright crystal is big.
    var scale: CGFloat = 1

    private static let kindColors: [ConsoleLog.Kind: Color] = [
        .status: Color(red: 0.73, green: 0.76, blue: 0.84),
        .command: Color(red: 0.56, green: 0.84, blue: 0.77),
        .feedback: Color(red: 0.95, green: 0.85, blue: 0.54),
        .error: Color(red: 1.0, green: 0.54, blue: 0.5),
    ]
    private static let letterColors: [String: Color] = [
        "X": Color(clay: Clay.orange), "Y": Color(clay: Clay.yellow),
        "B": Color(clay: Clay.teal), "A": Color(clay: Clay.coral),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            statusBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3 * scale) {
                        ForEach(model.console.lines) { line in
                            Text(line.text)
                                .foregroundStyle(Self.kindColors[line.kind] ?? .white)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.console.lines.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            HStack {
                ForEach(legend.indices, id: \.self) { i in
                    let item = legend[i]
                    Text("\(item.letter): \(item.meaning ?? "-")")
                        .foregroundStyle(item.meaning == nil ? Color.gray : Self.letterColors[item.letter] ?? .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
        .padding(8 * scale)
        .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).fill(Color(clay: Clay.screen)))
    }

    private var statusBar: some View {
        HStack(spacing: 6 * scale) {
            SignalBars(level: signalLevel)
            Text(model.link.stateText).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let rtt = model.console.latestRTT { Text("RTT \(rtt) ms").monospacedDigit() }
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
        .background(RoundedRectangle(cornerRadius: 6 * scale).fill(Color.white.opacity(0.08)))
    }

    /// 0...3 bars: off, reconnecting/connecting, slow link, good link.
    private var signalLevel: Int {
        switch model.link.state {
        case .ready: (model.console.latestRTT ?? 0) > 150 ? 2 : 3
        case .connecting, .reconnecting: 1
        default: 0
        }
    }
}

private struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? (level == 3 ? Color.green : Color.yellow) : Color.white.opacity(0.2))
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
    }
}

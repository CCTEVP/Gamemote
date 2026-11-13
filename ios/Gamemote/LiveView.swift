import SwiftUI
import GamemoteCore

/// Live mode: the clay controller and its console.
/// Sideways: the console is the small screen set into the controller (reference photo).
/// Upright: a compact controller at the bottom and a tall crystal console above it.
struct LiveView: View {
    let model: AppModel
    let back: () -> Void
    @State private var screenRect: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            let upright = geo.size.height > geo.size.width
            VStack(spacing: 0) {
                topBar
                if upright {
                    VStack(spacing: 12) {
                        CrystalConsole(model: model, legend: legend)
                        controller(layout: .compact)
                            .frame(height: min(geo.size.width * 0.55, geo.size.height * 0.4))
                    }
                    .padding(.horizontal, 16)
                } else {
                    controller(layout: .sideways)
                        .overlay(alignment: .topLeading) {
                            if screenRect.width > 0 {
                                ConsoleScreen(model: model, legend: legend, scale: screenRect.height / 160)
                                    .frame(width: screenRect.width, height: screenRect.height)
                                    .offset(x: screenRect.minX, y: screenRect.minY)
                            }
                        }
                }
            }
        }
        .background(Color(clay: Clay.table).ignoresSafeArea())
        .onDisappear { model.leaveLive() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Gamemote").font(.system(size: 22, weight: .bold, design: .rounded))
            Text(model.link.stateText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .opacity(0.7)
                .lineLimit(2)
            Spacer()
            Button("Back") { back() }.buttonStyle(PillButtonStyle())
        }
        .foregroundStyle(Color(clay: Clay.ink))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func controller(layout: ControllerLayout) -> some View {
        ControllerView(
            layout: layout,
            enabled: model.bindings.map { $0 != nil },
            onStick: { model.stick($0) },
            onButton: { model.button($0, pressed: $1) },
            onStop: { model.stop() },
            onScreenRect: { screenRect = $0 })
    }

    private var legend: [(letter: String, meaning: String?)] {
        // Legend order on the screen: X, Y, B, A (slots 0, 3, 1, 2).
        [0, 3, 1, 2].map { (ControllerARView.letters[$0], model.bindings[$0]?.name) }
    }
}

/// Upright: the console inside a clear, bevelled crystal block.
private struct CrystalConsole: View {
    let model: AppModel
    let legend: [(letter: String, meaning: String?)]

    var body: some View {
        ConsoleScreen(model: model, legend: legend, scale: 1.25)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.8, green: 0.9, blue: 0.97).opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            )
    }
}

// MARK: - Live bindings (stick, buttons, STOP) and their console lines

extension AppModel {
    /// What a face button does: fire an action, or hold a level channel while pressed.
    enum PadBinding: Equatable {
        case action(DeviceInfo.Action)
        case hold(DeviceInfo.Channel)

        var name: String {
            switch self {
            case .action(let a): a.name
            case .hold(let c): c.name
            }
        }
    }

    /// Slot 0 = first action, 1 = first level channel, 2 and 3 = further actions (as in the Godot app).
    var bindings: [PadBinding?] {
        let actions = link.info?.actions ?? []
        let level = link.info?.firstChannel(kind: "level")
        return [
            actions.first.map { .action($0) },
            level.map { .hold($0) },
            actions.count > 1 ? .action(actions[1]) : nil,
            actions.count > 2 ? .action(actions[2]) : nil,
        ]
    }

    /// Stick: x drives the first speed channel, y the first angle channel (neutral ± deflection × range).
    func stick(_ v: SIMD2<Float>) {
        guard let info = link.info else { return }
        var parts: [String] = []
        if let c = info.firstChannel(kind: "speed") {
            let value = Self.value(c, Double(v.x))
            link.setChannel(c.id, value)
            parts.append("\(c.name.lowercased()) \(value)")
        }
        if let c = info.firstChannel(kind: "angle") {
            let value = Self.value(c, Double(v.y))
            link.setChannel(c.id, value)
            parts.append("\(c.name.lowercased()) \(value)")
        }
        console.update(key: "stick", v == .zero ? "Stick: centred" : "Stick: " + parts.joined(separator: ", "))
    }

    static func value(_ c: DeviceInfo.Channel, _ d: Double) -> Int {
        let span = d >= 0 ? Double(c.max - c.neutral) : Double(c.neutral - c.min)
        return c.neutral + Int((d * span).rounded())
    }

    func button(_ slot: Int, pressed: Bool) {
        guard bindings.indices.contains(slot), let binding = bindings[slot] else { return }
        switch binding {
        case .action(let a):
            guard pressed else { return }
            link.trigger(a.id, params: a.params.map(\.default))
            console.add("Sent: \(a.name)", kind: .command)
        case .hold(let c):
            link.setChannel(c.id, pressed ? c.max : c.neutral)
            console.add(pressed ? "Holding: \(c.name)" : "Let go: \(c.name)", kind: .command)
        }
    }

    func stop() {
        link.stopAll()
        console.add("STOP sent: everything back to neutral", kind: .command)
    }

    /// Leaving Live leaves the gadget safe.
    func leaveLive() {
        if link.isReady { link.stopAll() }
    }
}

#Preview("Live, sideways", traits: .landscapeLeft) {
    LiveView(model: .preview(connected: true)) {}
}

#Preview("Live, upright") {
    LiveView(model: .preview(connected: true)) {}
}

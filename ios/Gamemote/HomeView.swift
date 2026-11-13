import SwiftUI
import GamemoteCore

/// Home: the connection, and the two modes (Live, Routine builder). The modes stay disabled,
/// with a plain reason, until a gadget is connected. Upright, everything stacks.
struct HomeView: View {
    let model: AppModel
    let open: (RootView.Mode) -> Void

    private var link: DeviceLink { model.link }

    var body: some View {
        GeometryReader { geo in
            let upright = geo.size.height > geo.size.width
            VStack(alignment: .leading, spacing: 14) {
                header(upright: upright)
                linkPicker
                tiles(upright: upright)
                Text(model.reason)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(clay: Clay.ink))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Color(clay: Clay.homeBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func header(upright: Bool) -> some View {
        let layout = upright ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text("Gamemote")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            if !upright { Spacer() }
            Text(link.stateText + (link.transportKind == .mock ? " (mock device)" : ""))
                .font(.system(size: 17, weight: .medium, design: .rounded))
            Button(model.isBusy ? "Disconnect" : "Connect") { model.connectOrDisconnect() }
                .buttonStyle(PillButtonStyle())
        }
        .foregroundStyle(Color(clay: Clay.ink))
    }

    private var linkPicker: some View {
        HStack(spacing: 8) {
            Text("Connect with")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(clay: Clay.ink))
            Button("Bluetooth") {}
                .buttonStyle(PillButtonStyle(color: Color(clay: Clay.disabled)))
                .disabled(true)   // the CoreBluetooth transport is the next step of the port
            Button("Mock device") {}
                .buttonStyle(PillButtonStyle())
                .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    private func tiles(upright: Bool) -> some View {
        let layout = upright ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            ModeTile(title: "Live", subtitle: "Drive your gadget with the gamepad",
                     color: Clay.mint, enabled: link.isReady) { open(.live) }
            ModeTile(title: "Routine builder", subtitle: "Snap blocks together to make a routine",
                     color: Clay.sky, enabled: false) {}
        }
    }
}

/// A big clay tile with a title and one line of description.
struct ModeTile: View {
    let title: String
    let subtitle: String
    let color: UIColor
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 15, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(clay: Clay.ink))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(clay: enabled ? color : Clay.disabled))
                    .shadow(color: .black.opacity(enabled ? 0.15 : 0), radius: 8, y: 5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview("Home, not connected", traits: .landscapeLeft) {
    HomeView(model: .preview(connected: false)) { _ in }
}

#Preview("Home, connected", traits: .landscapeLeft) {
    HomeView(model: .preview(connected: true)) { _ in }
}

#Preview("Home, upright") {
    HomeView(model: .preview(connected: true)) { _ in }
}

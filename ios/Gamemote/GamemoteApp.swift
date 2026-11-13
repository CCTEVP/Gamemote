import SwiftUI

@main
struct GamemoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

/// Home, and the mode chosen from it. Leaving a mode keeps the connection.
struct RootView: View {
    let model: AppModel
    @State private var mode: Mode?

    enum Mode: Hashable { case live }

    var body: some View {
        Group {
            switch mode {
            case .live:
                LiveView(model: model) { mode = nil }
            case nil:
                HomeView(model: model) { mode = $0 }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }
}

import SwiftUI

@main
struct PocketRooflineApp: App {
    @State private var modelStore: ModelStore
    @State private var conditions: DeviceConditions
    @State private var session: BenchmarkSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let modelStore = ModelStore()
        let conditions = DeviceConditions()
        _modelStore = State(initialValue: modelStore)
        _conditions = State(initialValue: conditions)
        _session = State(initialValue: BenchmarkSession(modelStore: modelStore, conditions: conditions))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(modelStore)
                .environment(conditions)
                .environment(session)
                .preferredColorScheme(.dark)
                .task { await modelStore.refresh() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseChanged(to: newPhase)
            if newPhase == .active { conditions.refresh() }
        }
    }
}

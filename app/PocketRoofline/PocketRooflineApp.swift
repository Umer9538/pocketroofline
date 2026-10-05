import SwiftUI

@main
struct PocketRooflineApp: App {
    @State private var modelStore: ModelStore
    @State private var conditions: DeviceConditions
    @State private var session: BenchmarkSession
    @State private var diagnostic: DiagnosticSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let modelStore = ModelStore()
        let conditions = DeviceConditions()
        let session = BenchmarkSession(modelStore: modelStore, conditions: conditions)
        _modelStore = State(initialValue: modelStore)
        _conditions = State(initialValue: conditions)
        _session = State(initialValue: session)
        _diagnostic = State(initialValue: DiagnosticSession(modelStore: modelStore, conditions: conditions, benchmark: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(modelStore)
                .environment(conditions)
                .environment(session)
                .environment(diagnostic)
                .preferredColorScheme(.dark)
                .task {
                    await modelStore.refresh()
                    // `-PocketRooflineAutoRun diagnostic` starts the diagnostic once the model is verified.
                    diagnostic.startIfRequestedAtLaunch()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseChanged(to: newPhase)
            diagnostic.scenePhaseChanged(to: newPhase)
            if newPhase == .active { conditions.refresh() }
        }
    }
}

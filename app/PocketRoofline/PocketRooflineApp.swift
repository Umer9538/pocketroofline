import SwiftUI

@main
struct PocketRooflineApp: App {
    @State private var modelStore: ModelStore
    @State private var conditions: DeviceConditions
    @State private var session: BenchmarkSession
    @State private var diagnostic: DiagnosticSession
    @State private var recovery: RecoverySession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let modelStore = ModelStore()
        let conditions = DeviceConditions()
        let session = BenchmarkSession(modelStore: modelStore, conditions: conditions)
        _modelStore = State(initialValue: modelStore)
        _conditions = State(initialValue: conditions)
        _session = State(initialValue: session)
        let diagnostic = DiagnosticSession(modelStore: modelStore, conditions: conditions, benchmark: session)
        _diagnostic = State(initialValue: diagnostic)
        _recovery = State(initialValue: RecoverySession(
            modelStore: modelStore, conditions: conditions, benchmark: session, diagnostic: diagnostic
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(modelStore)
                .environment(conditions)
                .environment(session)
                .environment(diagnostic)
                .environment(recovery)
                .preferredColorScheme(.dark)
                .task {
                    await modelStore.refresh()
                    // `-PocketRooflineAutoRun diagnostic|recovery` starts that run once the model is verified.
                    diagnostic.startIfRequestedAtLaunch()
                    recovery.startIfRequestedAtLaunch()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseChanged(to: newPhase)
            diagnostic.scenePhaseChanged(to: newPhase)
            recovery.scenePhaseChanged(to: newPhase)
            if newPhase == .active { conditions.refresh() }
        }
    }
}

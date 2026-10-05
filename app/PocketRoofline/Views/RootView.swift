import SwiftUI

/// Switches between the screens based on where the sessions are. A diagnostic run, while it runs
/// or shows its result, takes the screen; otherwise the benchmark session decides.
struct RootView: View {
    @Environment(BenchmarkSession.self) private var session
    @Environment(DiagnosticSession.self) private var diagnostic

    var body: some View {
        Group {
            switch diagnostic.phase {
            case .running(let status):
                DiagnosticRunView(status: status, onStop: diagnostic.stop)
            case .finished(let capture, let savedTo):
                DiagnosticResultView(capture: capture, savedTo: savedTo, onDone: diagnostic.reset)
            case .idle, .failed, .interrupted:
                benchmarkScreen
            }
        }
        .animation(.smooth, value: screen)
    }

    @ViewBuilder
    private var benchmarkScreen: some View {
        switch session.phase {
        case .preparing, .warmup, .running:
            RunView()
        case .finished(let capture, let savedTo):
            ResultView(capture: capture, savedTo: savedTo, curve: session.livePoints, onDone: session.reset)
        case .idle, .failed, .interrupted:
            HomeView()
        }
    }

    private enum Screen { case home, run, result, diagnosticRun, diagnosticResult }

    private var screen: Screen {
        switch diagnostic.phase {
        case .running: return .diagnosticRun
        case .finished: return .diagnosticResult
        case .idle, .failed, .interrupted: break
        }
        switch session.phase {
        case .preparing, .warmup, .running: return .run
        case .finished: return .result
        case .idle, .failed, .interrupted: return .home
        }
    }
}

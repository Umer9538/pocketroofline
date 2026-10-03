import SwiftUI

/// Switches between the three screens based on where the session is.
struct RootView: View {
    @Environment(BenchmarkSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .preparing, .warmup, .running:
                RunView()
            case .finished(let capture, let savedTo):
                ResultView(capture: capture, savedTo: savedTo, curve: session.livePoints, onDone: session.reset)
            case .idle, .failed, .interrupted:
                HomeView()
            }
        }
        .animation(.smooth, value: screen)
    }

    private enum Screen { case home, run, result }

    private var screen: Screen {
        switch session.phase {
        case .preparing, .warmup, .running: .run
        case .finished: .result
        case .idle, .failed, .interrupted: .home
        }
    }
}

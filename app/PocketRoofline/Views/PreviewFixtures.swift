#if DEBUG
import Foundation

/// Sample data for SwiftUI previews only; compiled out of release builds so it can never reach
/// the shipping UI. Repeat values are copied from the published iPhone 13 run in `results/`.
enum PreviewFixtures {
    static let capture = Capture(
        appVersion: "1.0 (1)",
        capturedAt: Date(timeIntervalSince1970: 1_788_462_036),
        matrixVersion: "v1",
        device: .init(model: "iPhone 13", identifier: "iPhone14,5", soc: "A15 Bionic", ramGB: 4),
        os: .init(name: "iOS", version: "26.6.1", build: "23G83"),
        backend: .init(
            name: "llama.cpp-metal",
            version: "b1 (source build)",
            commit: "95ef7fc16054e63b427a3ef00188e055ef7586d8",
            buildFlags: "build-xcframework.sh; GGML_METAL=ON; n_ctx=4096; batch=2048"
        ),
        model: .init(
            id: "TinyLlama-1.1B-1T-OpenOrca",
            params: 1.1,
            quant: "Q4_0",
            fileSha256: "bd07d1c53b833d422272259b17b393270b8f81c937d14332dfa044fe1b349884",
            tensorBytes: 635_990_016
        ),
        conditions: .init(charging: false, airplaneMode: true, batteryStartPct: 78, batteryEndPct: 71, lowPowerMode: false),
        regimes: [
            regime(.siso, 128, 128, [
                (527.949, 42.597, 242.448, .fair, .fair),
                (508.832, 42.439, 251.557, .fair, .fair),
                (486.717, 42.575, 262.986, .fair, .fair),
                (507.518, 43.202, 252.208, .fair, .fair),
                (489.185, 43.193, 261.660, .fair, .fair),
            ]),
            regime(.liso, 2048, 128, [
                (454.658, 43.246, 4504.486, .fair, .serious),
                (422.629, 42.428, 4845.857, .serious, .serious),
                (392.716, 42.302, 5214.967, .serious, .serious),
                (396.661, 42.507, 5163.095, .serious, .serious),
                (398.557, 42.427, 5138.541, .serious, .serious),
            ]),
            regime(.silo, 128, 1024, [
                (426.294, 40.526, 300.262, .serious, .serious),
                (491.962, 40.363, 260.182, .serious, .serious),
                (424.405, 37.535, 301.599, .serious, .serious),
                (367.350, 33.027, 348.442, .serious, .serious),
                (324.553, 30.933, 394.388, .serious, .serious),
            ]),
        ]
    )

    /// A stepped curve at each repeat's measured mean; real runs show per-window detail.
    static let livePoints: [LivePoint] = {
        var points: [LivePoint] = []
        var clock = 0.0
        for regime in capture.regimes {
            for repeatResult in regime.repeats {
                clock += repeatResult.ttftMs / 1000
                for tokensDone in stride(from: 16, through: regime.generateTokens, by: 16) {
                    clock += 16 / repeatResult.decodeTokensPerSec
                    points.append(LivePoint(
                        regime: regime.label,
                        repeatIndex: repeatResult.index,
                        tokensDone: tokensDone,
                        secondsSinceStart: clock,
                        tokensPerSecond: repeatResult.decodeTokensPerSec,
                        thermal: repeatResult.thermalStateEnd
                    ))
                }
                clock += 3
            }
        }
        return points
    }()

    /// The diagnostic's shape (SILO × 5, then SISO × 3) built from the same published repeats, every
    /// window at its repeat's measured mean. Real traces show per-window detail.
    static let diagnosticCapture: DiagnosticCapture = {
        let windowTokens = DiagnosticProtocol.windowTokens
        let pause = DiagnosticProtocol.pauseBetweenRepeats.secondsValue
        var clock = 0.0
        let regimes = DiagnosticProtocol.sequence.compactMap { block -> DiagnosticRegimeResult? in
            guard let source = capture.regime(block.regime.label) else { return nil }
            let repeats = source.repeats.prefix(block.repeats).map { repeatResult in
                let start = clock
                clock += repeatResult.ttftMs / 1000
                let windows = stride(from: windowTokens, through: source.generateTokens, by: windowTokens).map { tokensDone in
                    clock += Double(windowTokens) / repeatResult.decodeTokensPerSec
                    return DiagnosticWindow(
                        tokensDone: tokensDone,
                        tokensPerSec: repeatResult.decodeTokensPerSec,
                        secondsSinceStart: clock,
                        thermalState: repeatResult.thermalStateEnd
                    )
                }
                clock += pause
                return DiagnosticRepeat(
                    index: repeatResult.index,
                    startSeconds: start,
                    prefillTokensPerSec: repeatResult.prefillTokensPerSec,
                    decodeTokensPerSec: repeatResult.decodeTokensPerSec,
                    ttftMs: repeatResult.ttftMs,
                    peakResidentMB: repeatResult.peakResidentMB,
                    thermalStateStart: repeatResult.thermalStateStart,
                    thermalStateEnd: repeatResult.thermalStateEnd,
                    windows: windows
                )
            }
            return DiagnosticRegimeResult(
                label: source.label,
                promptTokens: source.promptTokens,
                generateTokens: source.generateTokens,
                repeats: repeats
            )
        }
        return DiagnosticCapture(
            appVersion: capture.appVersion,
            capturedAt: capture.capturedAt,
            device: capture.device,
            os: capture.os,
            backend: capture.backend,
            model: capture.model,
            conditions: capture.conditions,
            regimes: regimes
        )
    }()

    private static func regime(
        _ label: RegimeLabel,
        _ prompt: Int,
        _ generate: Int,
        _ repeats: [(Double, Double, Double, ThermalLevel, ThermalLevel)]
    ) -> RegimeResult {
        RegimeResult(
            label: label,
            promptTokens: prompt,
            generateTokens: generate,
            repeats: repeats.enumerated().map { index, values in
                RepeatResult(
                    index: index,
                    prefillTokensPerSec: values.0,
                    decodeTokensPerSec: values.1,
                    ttftMs: values.2,
                    peakResidentMB: nil,
                    thermalStateStart: values.3,
                    thermalStateEnd: values.4
                )
            }
        )
    }
}
#endif

import Charts
import SwiftUI

/// The diagnostic's result: every repeat's decode speed, and the window trace drawn once from the
/// finished capture. It shows the data and hands over the file. Reading it is the job of
/// `harness/diagnose.py`, on a Mac.
struct DiagnosticResultView: View {
    let capture: DiagnosticCapture
    let savedTo: URL?
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                notice
                VStack(alignment: .leading, spacing: 10) {
                    Text("Decode speed per \(capture.plan.windowTokens)-token window").font(.headline)
                    DiagnosticWindowChart(capture: capture).frame(height: 240)
                    Text("One line per repeat, in run order. Each point is the decode speed over one window of \(capture.plan.windowTokens) generated tokens.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .cardBackground()
                DiagnosticRepeatsTable(capture: capture)
                actions
                Button("Done", action: onDone)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostic run")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(capture.device.model) · \(capture.os.name) \(capture.os.version) (\(capture.os.build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not a benchmark result. It is saved as its own file (\(capture.matrixVersion)) and is never mixed into matrix v1. Read it on a Mac with harness/diagnose.py.", systemImage: "stethoscope")
            if let start = capture.thermalAtStart {
                Label(
                    start == .nominal
                        ? "Started cool (thermal Nominal)."
                        : "Started at thermal \(start.displayName), so this is not a cold start.",
                    systemImage: "thermometer.medium"
                )
                .foregroundStyle(start == .nominal ? Color.secondary : Color.orange)
            }
            if DeviceProfile.isSimulator {
                Label("Simulator run: llama.cpp on your Mac's CPU. It checks the pipeline only and says nothing about a phone.", systemImage: "desktopcomputer")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .cardBackground()
    }

    @ViewBuilder
    private var actions: some View {
        if let savedTo {
            HStack(spacing: 12) {
                ShareLink(item: savedTo) {
                    Label("Export JSON", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    openInFiles(savedTo)
                } label: {
                    Label("Show in Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Label("The capture couldn't be saved to Documents.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    /// The `shareddocuments` scheme opens the Files app at a path inside this app's Documents.
    private func openInFiles(_ url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "shareddocuments"
        if let filesURL = components?.url {
            openURL(filesURL)
        }
    }
}

/// Window decode speed against time since the first measured repeat, one line per repeat.
private struct DiagnosticWindowChart: View {
    let capture: DiagnosticCapture

    private struct Point: Identifiable {
        let regime: RegimeLabel
        let series: String
        let tokensDone: Int
        let seconds: Double
        let tokensPerSec: Double

        var id: String { "\(series)-\(tokensDone)" }
    }

    private var points: [Point] {
        capture.regimes.flatMap { regime in
            regime.repeats.flatMap { repeatResult in
                repeatResult.windows.map { window in
                    Point(
                        regime: regime.label,
                        series: "\(regime.label.rawValue)-\(repeatResult.index)",
                        tokensDone: window.tokensDone,
                        seconds: window.secondsSinceStart,
                        tokensPerSec: window.tokensPerSec
                    )
                }
            }
        }
    }

    var body: some View {
        let labels = capture.regimes.map(\.label)
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.seconds),
                y: .value("Decode tok/s", point.tokensPerSec),
                series: .value("Repeat", point.series)
            )
            .foregroundStyle(by: .value("Regime", point.regime.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            PointMark(
                x: .value("Time", point.seconds),
                y: .value("Decode tok/s", point.tokensPerSec)
            )
            .foregroundStyle(by: .value("Regime", point.regime.rawValue))
            .symbolSize(14)
        }
        .chartForegroundStyleScale(domain: labels.map(\.rawValue), range: labels.map(\.color))
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .accessibilityLabel("Decode speed per window over the diagnostic run")
    }
}

/// Every repeat in run order, with the change from its first to its last window.
private struct DiagnosticRepeatsTable: View {
    let capture: DiagnosticCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every repeat").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Run")
                    Text("Decode").gridColumnAlignment(.trailing)
                    Text("Prefill").gridColumnAlignment(.trailing)
                    Text("In-run").gridColumnAlignment(.trailing)
                    Text("Thermal")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(capture.regimes) { regime in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(regime.repeats) { repeatResult in
                        GridRow {
                            Text("\(regime.label.rawValue) \(repeatResult.index + 1)")
                                .foregroundStyle(regime.label.color)
                            Text(Format.tokensPerSecond(repeatResult.decodeTokensPerSec))
                            Text(repeatResult.prefillTokensPerSec.formatted(.number.precision(.fractionLength(0))))
                                .foregroundStyle(.secondary)
                            Text(repeatResult.windowChangePercent.map(Self.signedPercent) ?? "–")
                                .foregroundStyle(.secondary)
                            thermal(repeatResult)
                        }
                        .font(.metric(15, weight: .medium))
                    }
                }
            }
            // Colours as in ThermalLevel.color (Theme.swift).
            Text("tok/s. In-run: change from the repeat's first window to its last. Thermal, start → end: green nominal, yellow fair, orange serious, red critical.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    private static func signedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%"
    }

    private func thermal(_ repeatResult: DiagnosticRepeat) -> some View {
        HStack(spacing: 4) {
            Circle().fill(repeatResult.thermalStateStart.color).frame(width: 7, height: 7)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Circle().fill(repeatResult.thermalStateEnd.color).frame(width: 7, height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal \(repeatResult.thermalStateStart.rawValue) to \(repeatResult.thermalStateEnd.rawValue)")
    }
}

#if DEBUG
#Preview {
    DiagnosticResultView(capture: PreviewFixtures.diagnosticCapture, savedTo: nil, onDone: {})
}
#endif

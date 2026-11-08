import Charts
import SwiftUI

/// The recovery test's result: each probe's decode speed against its rest, the heat-phase
/// repeats, and the file. The chart is drawn once from the finished capture. Reading it is the job
/// of `harness/recovery.py`, on a Mac.
struct RecoveryResultView: View {
    let capture: RecoveryCapture
    let savedTo: URL?
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                notice
                VStack(alignment: .leading, spacing: 10) {
                    Text("Probe decode speed after each rest").font(.headline)
                    RecoveryProbeChart(capture: capture).frame(height: 220)
                    Text(chartCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .cardBackground()
                RecoveryProbesTable(capture: capture)
                RecoveryHeatTable(capture: capture)
                actions
                Button("Done", action: onDone)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var chartCaption: String {
        var text = "One probe (SISO 128→128) after each rest. Rests are cumulative: the phone keeps cooling through every rest and probe."
        if capture.coldWindowRate != nil {
            text += " Dashed line: the first \(capture.plan.windowTokens)-token window of heat repeat 1, the coolest point of the run."
        }
        return text
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery test")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(capture.device.model) · \(capture.os.name) \(capture.os.version) (\(capture.os.build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not a benchmark result. It is saved as its own file (\(capture.matrixVersion)) and is never mixed into matrix v1. Read it on a Mac with harness/recovery.py.", systemImage: "thermometer.snowflake")
            if capture.isScaled {
                Label("Scaled rests (×\(capture.plan.restScale.formatted())): a debug pipeline check, not a real run.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let start = capture.thermalAtStart {
                Label(
                    start == .nominal
                        ? "Started cool (thermal Nominal)."
                        : "Started at thermal \(start.displayName), so the cold reference is not from a cold phone.",
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

enum RecoveryFormat {
    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + " s"
    }

    static func percent(_ value: Double, of reference: Double?) -> String {
        guard let reference, reference > 0 else { return "–" }
        return (value / reference * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

/// Probe decode against rest length, one point per rung, with the cold reference as a rule.
private struct RecoveryProbeChart: View {
    let capture: RecoveryCapture

    private struct Point: Identifiable {
        let rest: String
        let tokensPerSec: Double
        let thermal: ThermalLevel
        var id: String { rest }
    }

    private var points: [Point] {
        capture.probes.map {
            Point(rest: RecoveryFormat.seconds($0.restSecondsPlanned), tokensPerSec: $0.result.decodeTokensPerSec,
                  thermal: $0.thermalAtRestEnd)
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Rest", point.rest), y: .value("Decode tok/s", point.tokensPerSec))
                    .foregroundStyle(RegimeLabel.siso.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Rest", point.rest), y: .value("Decode tok/s", point.tokensPerSec))
                    .foregroundStyle(point.thermal.color)
                    .symbolSize(60)
            }
            if let cold = capture.coldWindowRate {
                RuleMark(y: .value("Cold", cold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxisLabel("Rest before the probe")
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .accessibilityLabel("Probe decode speed after each rest")
    }
}

/// Every probe, with its share of the cold reference and the thermal state around it.
private struct RecoveryProbesTable: View {
    let capture: RecoveryCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Probes").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Rest")
                    Text("Since heat").gridColumnAlignment(.trailing)
                    Text("Decode").gridColumnAlignment(.trailing)
                    Text("Cold").gridColumnAlignment(.trailing)
                    Text("Thermal")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(capture.probes) { probe in
                    GridRow {
                        Text(RecoveryFormat.seconds(probe.restSecondsPlanned))
                        Text(RecoveryFormat.seconds(probe.secondsSinceHeatEnd)).foregroundStyle(.secondary)
                        Text(Format.tokensPerSecond(probe.result.decodeTokensPerSec))
                        Text(RecoveryFormat.percent(probe.result.decodeTokensPerSec, of: capture.coldWindowRate))
                            .foregroundStyle(.secondary)
                        ThermalDots(states: [probe.thermalAtRestStart, probe.thermalAtRestEnd, probe.thermalAtProbeEnd])
                    }
                    .font(.metric(15, weight: .medium))
                }
            }
            Text("tok/s. Since heat: from the end of the heat phase to the probe's start. Cold: share of heat repeat 1's first window. Thermal: rest start → rest end → probe end.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }
}

/// The heat-phase repeats, with the change from each one's first window to its last.
private struct RecoveryHeatTable: View {
    let capture: RecoveryCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Heat phase").font(.headline)
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
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(capture.heat) { repeatResult in
                    GridRow {
                        Text("\(capture.plan.heat.label.rawValue) \(repeatResult.index + 1)")
                            .foregroundStyle(capture.plan.heat.label.color)
                        Text(Format.tokensPerSecond(repeatResult.decodeTokensPerSec))
                        Text(repeatResult.prefillTokensPerSec.formatted(.number.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                        Text(repeatResult.windowChangePercent.map(Self.signedPercent) ?? "–")
                            .foregroundStyle(.secondary)
                        ThermalDots(states: [repeatResult.thermalStateStart, repeatResult.thermalStateEnd])
                    }
                    .font(.metric(15, weight: .medium))
                }
            }
            // Colours as in ThermalLevel.color (Theme.swift).
            Text("tok/s. In-run: change from the repeat's first window to its last. Thermal dots: green nominal, yellow fair, orange serious, red critical.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    private static func signedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())) + "%"
    }
}

private struct ThermalDots: View {
    let states: [ThermalLevel]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(states.enumerated()), id: \.offset) { offset, state in
                if offset > 0 {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Circle().fill(state.color).frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal " + states.map(\.rawValue).joined(separator: " to "))
    }
}

#if DEBUG
#Preview {
    RecoveryResultView(capture: PreviewFixtures.recoveryCapture, savedTo: nil, onDone: {})
}
#endif

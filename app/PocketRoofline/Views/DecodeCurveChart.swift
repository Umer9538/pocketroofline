import Charts
import SwiftUI

/// Decode tok/s over time, one segment per repeat, coloured by regime.
struct DecodeCurveChart: View {
    let points: [LivePoint]
    var showsAxes = true

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.secondsSinceStart),
                y: .value("Decode tok/s", point.tokensPerSecond),
                series: .value("Repeat", point.seriesID)
            )
            .foregroundStyle(by: .value("Regime", point.regime.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(
            domain: RegimeLabel.allCases.map(\.rawValue),
            range: RegimeLabel.allCases.map(\.color)
        )
        .chartXScale(domain: .automatic(includesZero: false))
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
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .chartLegend(showsAxes ? .visible : .hidden)
        .accessibilityLabel("Decode speed over time")
    }
}

#if DEBUG
#Preview {
    DecodeCurveChart(points: PreviewFixtures.livePoints)
        .frame(height: 260)
        .padding()
}
#endif

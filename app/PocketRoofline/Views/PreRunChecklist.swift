import SwiftUI

/// Live protocol checks. None of them block a run: conditions are recorded either way,
/// and a warm or plugged-in run is still an honest data point if it is labelled as one.
struct PreRunChecklist: View {
    @Environment(DeviceConditions.self) private var conditions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you run")
                .font(.headline)
            ChecklistRow(status: thermal.status, title: "Thermal state: \(conditions.thermal.displayName)", detail: thermal.detail)
            ChecklistRow(status: power.status, title: power.title, detail: power.detail)
            ChecklistRow(
                status: conditions.isLowPowerModeEnabled ? .warning : .ok,
                title: conditions.isLowPowerModeEnabled ? "Low Power Mode is on" : "Low Power Mode is off",
                detail: conditions.isLowPowerModeEnabled ? "It caps performance. Turn it off in Settings › Battery." : nil
            )
            ChecklistRow(status: network.status, title: network.title, detail: network.detail)
        }
        .cardBackground()
        .animation(.default, value: conditions.thermal)
    }

    private var thermal: (status: ChecklistRow.Status, detail: String?) {
        conditions.thermal == .nominal
            ? (.ok, nil)
            : (.warning, "Let it cool for a cold-start run. A warm start is recorded as such.")
    }

    private var power: (status: ChecklistRow.Status, title: String, detail: String?) {
        let battery = conditions.batteryPercent.map { " · battery \(Int($0))%" } ?? ""
        switch conditions.isOnExternalPower {
        case true?: return (.warning, "Plugged in\(battery)", "Unplug: charging adds heat and changes power limits.")
        case false?: return (.ok, "On battery\(battery)", nil)
        case nil: return (.advice, "Power state unavailable", "Run unplugged for a fair result.")
        }
    }

    private var network: (status: ChecklistRow.Status, title: String, detail: String?) {
        switch conditions.hasNetworkPath {
        case false?: (.ok, "No network connection", "Radios look off, as recommended.")
        case true?: (.advice, "Network is on", "Airplane mode is recommended once the model is downloaded.")
        case nil: (.advice, "Checking network…", nil)
        }
    }
}

struct ChecklistRow: View {
    enum Status {
        case ok, advice, warning

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .advice: "info.circle.fill"
            case .warning: "exclamationmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ok: .green
            case .advice: .blue
            case .warning: .orange
            }
        }
    }

    let status: Status
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

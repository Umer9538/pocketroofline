import Foundation
import Network
import Observation
import UIKit

/// Live view of the run conditions the protocol cares about: heat, power, and radios.
///
/// Created once for the app's lifetime, so its observers are never torn down.
@MainActor
@Observable
final class DeviceConditions {
    private(set) var thermal: ThermalLevel = .current
    private(set) var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    /// 0...100, or nil where iOS can't report it (the simulator).
    private(set) var batteryPercent: Double?
    /// Whether any network interface is usable. Nil until the first path update arrives.
    private(set) var hasNetworkPath: Bool?

    /// Plugged in, whether or not the battery is still filling. Nil where iOS can't tell (the simulator).
    var isOnExternalPower: Bool? {
        switch batteryState {
        case .charging, .full: true
        case .unplugged: false
        case .unknown: nil
        @unknown default: nil
        }
    }

    @ObservationIgnored private let pathMonitor = NWPathMonitor()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        startObserving()
    }

    func refresh() {
        thermal = .current
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        batteryState = UIDevice.current.batteryState
        let level = UIDevice.current.batteryLevel
        batteryPercent = level < 0 ? nil : (Double(level) * 100).rounded()
    }

    private func startObserving() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let usable = path.status == .satisfied
            Task { @MainActor in self?.hasNetworkPath = usable }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.umer9538.pocketroofline.network"))

        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
            UIDevice.batteryStateDidChangeNotification,
            UIDevice.batteryLevelDidChangeNotification,
        ]
        for name in names {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                    self?.refresh()
                }
            }
        }
    }
}

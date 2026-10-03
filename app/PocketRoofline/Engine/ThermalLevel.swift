import Foundation

/// `ProcessInfo.ThermalState` with the string encoding the run schema uses.
enum ThermalLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        // A state this build doesn't know can't be shown to be cool, so assume the worst
        // rather than risk recording a cold start that never happened.
        @unknown default: self = .critical
        }
    }

    /// Safe to call from any thread; `ProcessInfo` is thread-safe.
    static var current: ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }

    var displayName: String { rawValue.capitalized }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.severity < rhs.severity
    }

    private var severity: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }
}

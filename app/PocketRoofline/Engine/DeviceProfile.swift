import Foundation
import UIKit

/// Who ran the benchmark: hardware and OS facts that don't change during a run.
struct DeviceProfile: Sendable, Hashable {
    let identifier: String
    let marketingName: String
    let soc: String
    /// Measured from `ProcessInfo.physicalMemory`, never looked up in a table.
    let ramGB: Int
    let osName: String
    let osVersion: String
    let osBuild: String

    /// Simulator runs use the host Mac's CPU, so their numbers must never pass for phone data.
    #if targetEnvironment(simulator)
    static let isSimulator = true
    #else
    static let isSimulator = false
    #endif

    @MainActor
    static func current() -> DeviceProfile {
        let identifier = hardwareIdentifier()
        let known = knownModels[identifier]
        let name: String
        let soc: String
        #if targetEnvironment(simulator)
        name = "\(known?.name ?? identifier) (Simulator)"
        soc = "Simulator on host Mac"
        #else
        name = known?.name ?? "Unknown iPhone (\(identifier))"
        soc = known?.soc ?? "unknown"
        #endif

        // iOS reports less than the installed DRAM (an 8 GB iPhone shows about 7.5 GiB), so
        // rounding up recovers the installed size where rounding to nearest would undercount.
        let gibibytes = Double(ProcessInfo.processInfo.physicalMemory) / Double(1 << 30)
        return DeviceProfile(
            identifier: identifier,
            marketingName: name,
            soc: soc,
            ramGB: Int(gibibytes.rounded(.up)),
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            osBuild: osBuild()
        )
    }

    private static func hardwareIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #endif
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func osBuild() -> String {
        #if targetEnvironment(simulator)
        // In the simulator, kern.osversion reports the host Mac's build, not the runtime's.
        if let runtime = ProcessInfo.processInfo.environment["SIMULATOR_RUNTIME_BUILD_VERSION"] {
            return runtime
        }
        #endif
        return sysctlString("kern.osversion") ?? "unknown"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static let knownModels: [String: (name: String, soc: String)] = [
        "iPhone12,1": ("iPhone 11", "A13 Bionic"),
        "iPhone12,3": ("iPhone 11 Pro", "A13 Bionic"),
        "iPhone12,5": ("iPhone 11 Pro Max", "A13 Bionic"),
        "iPhone12,8": ("iPhone SE (2nd generation)", "A13 Bionic"),
        "iPhone13,1": ("iPhone 12 mini", "A14 Bionic"),
        "iPhone13,2": ("iPhone 12", "A14 Bionic"),
        "iPhone13,3": ("iPhone 12 Pro", "A14 Bionic"),
        "iPhone13,4": ("iPhone 12 Pro Max", "A14 Bionic"),
        "iPhone14,4": ("iPhone 13 mini", "A15 Bionic"),
        "iPhone14,5": ("iPhone 13", "A15 Bionic"),
        "iPhone14,2": ("iPhone 13 Pro", "A15 Bionic"),
        "iPhone14,3": ("iPhone 13 Pro Max", "A15 Bionic"),
        "iPhone14,6": ("iPhone SE (3rd generation)", "A15 Bionic"),
        "iPhone14,7": ("iPhone 14", "A15 Bionic"),
        "iPhone14,8": ("iPhone 14 Plus", "A15 Bionic"),
        "iPhone15,2": ("iPhone 14 Pro", "A16 Bionic"),
        "iPhone15,3": ("iPhone 14 Pro Max", "A16 Bionic"),
        "iPhone15,4": ("iPhone 15", "A16 Bionic"),
        "iPhone15,5": ("iPhone 15 Plus", "A16 Bionic"),
        "iPhone16,1": ("iPhone 15 Pro", "A17 Pro"),
        "iPhone16,2": ("iPhone 15 Pro Max", "A17 Pro"),
        "iPhone17,3": ("iPhone 16", "A18"),
        "iPhone17,4": ("iPhone 16 Plus", "A18"),
        "iPhone17,1": ("iPhone 16 Pro", "A18 Pro"),
        "iPhone17,2": ("iPhone 16 Pro Max", "A18 Pro"),
        "iPhone17,5": ("iPhone 16e", "A18"),
        "iPhone18,3": ("iPhone 17", "A19"),
        "iPhone18,4": ("iPhone Air", "A19 Pro"),
        "iPhone18,1": ("iPhone 17 Pro", "A19 Pro"),
        "iPhone18,2": ("iPhone 17 Pro Max", "A19 Pro"),
    ]
}

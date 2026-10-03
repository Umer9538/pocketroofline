import Darwin

enum ProcessMemory {
    /// Current resident set size in MB, or nil if the kernel won't say.
    ///
    /// Published captures record this sampled right after each repeat under the name
    /// `peakResidentMB`; the app keeps that exact method so its numbers stay comparable.
    static func residentMegabytes() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1024 / 1024
    }
}

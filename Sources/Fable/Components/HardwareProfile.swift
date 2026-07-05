import Foundation
import IOKit

/// What this Mac actually is — chip, unified memory, core counts — so Fable
/// can recommend performance settings for THIS machine instead of a generic
/// one, and say so honestly in the UI.
struct HardwareProfile: Equatable, Sendable {
    var chipName: String          // "Apple M4 Pro"
    var modelIdentifier: String   // "Mac16,8"
    var memoryBytes: Int64
    var performanceCores: Int
    var efficiencyCores: Int
    var gpuCores: Int?

    /// Marketing-rounded unified memory ("24 GB", not "23.99").
    var memoryGB: Int { Int((Double(memoryBytes) / 1_073_741_824).rounded()) }

    /// Chip class — the coarse performance lever.
    enum ChipTier: Equatable, Sendable {
        case base      // M1/M2/M3/M4
        case pro
        case max
        case ultra
        case other     // Intel or unrecognized
    }

    var chipTier: ChipTier { Self.tier(fromBrand: chipName) }

    /// Pure so it's testable against real brand strings.
    static func tier(fromBrand brand: String) -> ChipTier {
        let lower = brand.lowercased()
        guard lower.contains("apple m") else { return .other }
        if lower.hasSuffix("ultra") { return .ultra }
        if lower.hasSuffix("max") { return .max }
        if lower.hasSuffix("pro") { return .pro }
        return .base
    }

    /// One line for the UI: "Apple M4 Pro · 24 GB · 8P+4E · 16-core GPU".
    var summary: String {
        var parts = [chipName, "\(memoryGB) GB"]
        if performanceCores > 0 {
            parts.append("\(performanceCores)P+\(efficiencyCores)E")
        }
        if let gpuCores {
            parts.append("\(gpuCores)-core GPU")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Detection

    /// Detected once at startup; sysctl + IORegistry reads are cheap.
    static let current: HardwareProfile = detect()

    static func detect() -> HardwareProfile {
        HardwareProfile(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "Unknown",
            modelIdentifier: sysctlString("hw.model") ?? "Mac",
            memoryBytes: sysctlInt("hw.memsize") ?? 0,
            performanceCores: Int(sysctlInt("hw.perflevel0.physicalcpu") ?? 0),
            efficiencyCores: Int(sysctlInt("hw.perflevel1.physicalcpu") ?? 0),
            gpuCores: detectGPUCores()
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// Apple-silicon GPU core count from the AGXAccelerator service.
    private static func detectGPUCores() -> Int? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AGXAccelerator")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int else { return nil }
        return property
    }
}

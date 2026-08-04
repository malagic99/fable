import Foundation

/// Minimal Mach-O header inspection — the host-side counterpart to ``PEInfo``.
///
/// `PEInfo` answers "what is this *Windows guest* binary?". This answers "what
/// is this *macOS host* binary?" — which for Fable means the one question the
/// whole backend stack rests on: is the Wine build we're about to run x86_64
/// (so Rosetta 2 translates it) or native arm64?
///
/// That single bit decides Wine's dispatch-directory names (``WineLayout``) and
/// whether the Rosetta-only env vars in ``WineEnv`` mean anything. Note that
/// `sysctl.proc_translated` can't answer it: Fable itself is a native arm64
/// app, so asking about *our own* process always returns "not translated" no
/// matter what the backend is. The binary's own header is the honest source.
///
/// See docs/FEX-MIGRATION.md.
enum MachOInfo {
    enum Architecture: Equatable, Sendable {
        /// Intel — on Apple Silicon this only runs under Rosetta 2.
        case x86_64
        /// Native Apple Silicon.
        case arm64
        /// Universal (fat) binary; `hasARM64` decides how it actually runs.
        case universal(hasARM64: Bool)

        /// True when running this on Apple Silicon needs Rosetta 2. A fat
        /// binary with an arm64 slice runs native — the loader prefers it.
        var needsRosetta: Bool {
            switch self {
            case .x86_64: true
            case .arm64: false
            case .universal(let hasARM64): !hasARM64
            }
        }
    }

    // Mach-O `cputype` values (mach/machine.h). The 0x0100_0000 bit is
    // CPU_ARCH_ABI64.
    private static let cpuTypeX86_64: UInt32 = 0x0100_0007
    private static let cpuTypeARM64: UInt32 = 0x0100_000C

    static func architecture(of url: URL) -> Architecture? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 0x1000) else { return nil }
        try? handle.close()
        return architecture(of: head)
    }

    static func architecture(of data: Data) -> Architecture? {
        guard data.count >= 8 else { return nil }

        switch readU32LE(data, 0) {
        // MH_MAGIC_64 — a thin 64-bit image; cputype is the next word.
        case 0xFEED_FACF:
            return thin(cpuType: readU32LE(data, 4))
        // FAT_MAGIC (0xCAFEBABE) is stored big-endian, so it reads back
        // byte-swapped. Every field in a fat header is big-endian too.
        case 0xBEBA_FECA:
            return fat(data)
        default:
            // 32-bit (MH_MAGIC) and anything unrecognized: not a host binary
            // we know how to run.
            return nil
        }
    }

    private static func thin(cpuType: UInt32) -> Architecture? {
        switch cpuType {
        case cpuTypeX86_64: .x86_64
        case cpuTypeARM64: .arm64
        default: nil
        }
    }

    /// Walks the fat header's arch table looking for an arm64 slice.
    private static func fat(_ data: Data) -> Architecture? {
        let count = Int(readU32BE(data, 4))
        // Sanity bound: a real fat binary has a handful of slices, and this
        // count comes straight off disk.
        guard count > 0, count < 64 else { return nil }

        let entrySize = 20  // struct fat_arch
        var hasARM64 = false
        for index in 0..<count {
            let offset = 8 + index * entrySize
            guard offset + 4 <= data.count else { break }
            if readU32BE(data, offset) == cpuTypeARM64 { hasARM64 = true }
        }
        return .universal(hasARM64: hasARM64)
    }

    private static func readU32LE(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16
            | UInt32(data[base + 3]) << 24
    }

    private static func readU32BE(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base]) << 24
            | UInt32(data[base + 1]) << 16
            | UInt32(data[base + 2]) << 8
            | UInt32(data[base + 3])
    }
}

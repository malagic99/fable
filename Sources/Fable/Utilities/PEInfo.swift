import Foundation

/// Minimal PE header inspection — enough to know how to run a binary.
enum PEInfo {
    enum Architecture {
        /// 32-bit (PE32) — crashes Wine's WoW64 in several installer
        /// unpackers; prefer the compatibility runtime.
        case pe32
        /// 64-bit (PE32+).
        case pe64
    }

    static func architecture(of url: URL) -> Architecture? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 0x1000) else { return nil }
        try? handle.close()
        return architecture(of: head)
    }

    static func architecture(of data: Data) -> Architecture? {
        guard data.count > 0x40, data[data.startIndex] == 0x4D, data[data.startIndex + 1] == 0x5A else {
            return nil
        }
        let peOffset = Int(readU32(data, 0x3C))
        guard peOffset > 0, peOffset + 26 <= data.count,
              readU32(data, peOffset) == 0x0000_4550 else { return nil }

        let magic = readU16(data, peOffset + 24)
        switch magic {
        case 0x10B: return .pe32
        case 0x20B: return .pe64
        default: return nil
        }
    }

    /// True for a console program (`IMAGE_SUBSYSTEM_WINDOWS_CUI`, e.g.
    /// cmd.exe). Run like a game — output to a log, no console attached —
    /// it prints its prompt, reads no input, and exits before anything
    /// shows; it needs a console window (`wineconsole`).
    static func isConsoleProgram(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 0x1000) else { return false }
        try? handle.close()
        return subsystem(of: head) == consoleSubsystem
    }

    static let consoleSubsystem: UInt16 = 3

    /// The optional header's Subsystem field (2 = GUI, 3 = console) — at the
    /// same offset in PE32 and PE32+.
    static func subsystem(of data: Data) -> UInt16? {
        guard architecture(of: data) != nil else { return nil }
        let peOffset = Int(readU32(data, 0x3C))
        let field = peOffset + 24 + 68
        guard field + 2 <= data.count else { return nil }
        return readU16(data, field)
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset])
            | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for i in (0..<4).reversed() {
            value = value << 8 | UInt32(data[data.startIndex + offset + i])
        }
        return value
    }
}

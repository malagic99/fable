import Foundation

/// Reads and adds `LC_RPATH` entries in a Mach-O file — what
/// `otool -l` and `install_name_tool -add_rpath` do.
///
/// Fable did this with those two tools until v1.2.0. They are not part of
/// macOS: on a Mac without Xcode's Command Line Tools, `/usr/bin/otool` and
/// `/usr/bin/install_name_tool` are stubs that pop Apple's "install developer
/// tools" dialog and fail. Every engine needs an rpath added when it is
/// assembled (so `d3d12.so` can find D3DMetal, and the wineserver its
/// libraries), so on a clean Mac the engines came out broken. Homebrew
/// installs the tools, which is why no test Mac ever showed it.
///
/// An rpath is one load command appended to the header. The linker leaves
/// zeroed padding after the load commands for exactly this, so nothing else
/// in the file moves. The file's code signature is invalid afterwards and
/// must be redone (`/usr/bin/codesign`, which *is* part of macOS).
///
/// Thin 64-bit little-endian images only — every binary the engines ship.
enum MachORpath {
    enum RpathError: LocalizedError, Equatable {
        case notMachO64
        case malformed
        case noRoom(needed: Int, available: Int)

        var errorDescription: String? {
            switch self {
            case .notMachO64:
                "The file isn't a 64-bit Mach-O image."
            case .malformed:
                "The file's Mach-O header is damaged."
            case .noRoom(let needed, let available):
                "The file's header has no room for another library path (needs \(needed) bytes, has \(available))."
            }
        }
    }

    private static let magic64: UInt32 = 0xFEED_FACF
    private static let headerSize = 32
    private static let lcRpath: UInt32 = 0x8000_001C
    private static let lcSegment64: UInt32 = 0x19

    /// The rpaths in the image, in order.
    static func rpaths(in data: Data) throws -> [String] {
        var result: [String] = []
        try forEachCommand(in: data) { command, offset, size in
            guard command == lcRpath, size >= 12 else { return }
            let pathOffset = Int(u32(data, offset + 8))
            guard pathOffset >= 12, pathOffset < size else { throw RpathError.malformed }
            let bytes = data[(data.startIndex + offset + pathOffset)..<(data.startIndex + offset + size)]
            result.append(String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self))
        }
        return result
    }

    static func rpaths(of file: URL) throws -> [String] {
        try rpaths(in: Data(contentsOf: file, options: .mappedIfSafe))
    }

    /// The image with `rpath` added, or unchanged if it is already there.
    static func adding(_ rpath: String, to data: Data) throws -> Data {
        guard try !rpaths(in: data).contains(rpath) else { return data }

        // cmd, cmdsize, path offset (always 12), then the string, NUL-ended
        // and padded to 8 bytes — the layout install_name_tool writes.
        let size = (12 + rpath.utf8.count + 1 + 7) & ~7
        let commandCount = Int(u32(data, 16))
        let commandsSize = Int(u32(data, 20))
        let end = headerSize + commandsSize

        // The padding runs from the last load command to the first byte any
        // section stores in the file.
        var firstContent = data.count
        try forEachCommand(in: data) { command, offset, commandSize in
            guard command == lcSegment64, commandSize >= 72 else { return }
            let sectionCount = Int(u32(data, offset + 64))
            guard 72 + sectionCount * 80 <= commandSize else { throw RpathError.malformed }
            for index in 0..<sectionCount {
                let section = offset + 72 + index * 80
                let fileOffset = Int(u32(data, section + 48))
                let sectionSize = u64(data, section + 40)
                if fileOffset > 0, sectionSize > 0 { firstContent = min(firstContent, fileOffset) }
            }
        }
        let available = firstContent - end
        guard available >= size else { throw RpathError.noRoom(needed: size, available: max(0, available)) }
        // Anything but zeros there is content this would overwrite.
        guard data[(data.startIndex + end)..<(data.startIndex + end + size)].allSatisfy({ $0 == 0 }) else {
            throw RpathError.noRoom(needed: size, available: 0)
        }

        var command = Data(count: size)
        putU32(&command, 0, lcRpath)
        putU32(&command, 4, UInt32(size))
        putU32(&command, 8, 12)
        command.replaceSubrange(12..<(12 + rpath.utf8.count), with: Array(rpath.utf8))

        var patched = data
        patched.replaceSubrange((patched.startIndex + end)..<(patched.startIndex + end + size), with: command)
        putU32(&patched, 16, UInt32(commandCount + 1))
        putU32(&patched, 20, UInt32(commandsSize + size))
        return patched
    }

    /// Adds `rpath` to the file in place. Returns false when it was already
    /// there (nothing written). The caller re-signs the file.
    @discardableResult
    static func add(_ rpath: String, to file: URL) throws -> Bool {
        let original = try Data(contentsOf: file)
        let patched = try adding(rpath, to: original)
        guard patched != original else { return false }
        // Same inode and permissions: the file is executable and may be a
        // hard-link target.
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: patched)
        return true
    }

    // MARK: Parsing

    private static func forEachCommand(
        in data: Data, _ body: (_ command: UInt32, _ offset: Int, _ size: Int) throws -> Void
    ) throws {
        guard data.count >= headerSize, u32(data, 0) == magic64 else { throw RpathError.notMachO64 }
        let count = Int(u32(data, 16))
        let total = Int(u32(data, 20))
        guard headerSize + total <= data.count else { throw RpathError.malformed }
        var offset = headerSize
        for _ in 0..<count {
            guard offset + 8 <= headerSize + total else { throw RpathError.malformed }
            let size = Int(u32(data, offset + 4))
            guard size >= 8, offset + size <= headerSize + total else { throw RpathError.malformed }
            try body(u32(data, offset), offset, size)
            offset += size
        }
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start]) | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(u32(data, offset)) | UInt64(u32(data, offset + 4)) << 32
    }

    private static func putU32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        let start = data.startIndex + offset
        for index in 0..<4 { data[start + index] = UInt8((value >> (8 * UInt32(index))) & 0xFF) }
    }
}

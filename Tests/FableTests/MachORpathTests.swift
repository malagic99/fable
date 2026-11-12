import Foundation
import Testing
@testable import Fable

/// Engine assembly must not need Xcode's Command Line Tools: `otool` and
/// `install_name_tool` are stubs on a Mac without them (found after v1.2.0).
@Suite("Mach-O rpath editing")
struct MachORpathTests {

    /// A minimal thin 64-bit image: header, one segment with one section
    /// whose contents start at `contentOffset`, optional rpaths, zero padding.
    private func image(rpaths: [String] = [], contentOffset: Int = 0x400) -> Data {
        func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } }
        func u64(_ value: UInt64) -> [UInt8] { u32(UInt32(value & 0xFFFF_FFFF)) + u32(UInt32(value >> 32)) }
        func name(_ text: String) -> [UInt8] { Array(text.utf8) + [UInt8](repeating: 0, count: 16 - text.utf8.count) }

        var commands: [UInt8] = []
        // LC_SEGMENT_64, one section.
        commands += u32(0x19) + u32(72 + 80) + name("__TEXT")
        commands += u64(0) + u64(0x1000) + u64(0) + u64(0x1000) + u32(7) + u32(5) + u32(1) + u32(0)
        commands += name("__text") + name("__TEXT") + u64(UInt64(contentOffset)) + u64(16)
        commands += u32(UInt32(contentOffset)) + u32(0) + u32(0) + u32(0) + u32(0) + u32(0) + u32(0) + u32(0)
        var count: UInt32 = 1
        for rpath in rpaths {
            let size = (12 + rpath.utf8.count + 1 + 7) & ~7
            commands += u32(0x8000_001C) + u32(UInt32(size)) + u32(12) + Array(rpath.utf8)
            commands += [UInt8](repeating: 0, count: size - 12 - rpath.utf8.count)
            count += 1
        }
        var bytes = u32(0xFEED_FACF) + u32(0x0100_0007) + u32(3) + u32(6)
        bytes += u32(count) + u32(UInt32(commands.count)) + u32(0) + u32(0)
        bytes += commands
        bytes += [UInt8](repeating: 0, count: contentOffset - bytes.count)
        bytes += [UInt8](repeating: 0xC3, count: 16)
        return Data(bytes)
    }

    @Test
    func readsTheRpathsInOrder() throws {
        #expect(try MachORpath.rpaths(in: image()) == [])
        #expect(try MachORpath.rpaths(in: image(rpaths: ["@loader_path", "/opt/x"])) == ["@loader_path", "/opt/x"])
    }

    @Test
    func addsAnRpathWithoutMovingAnythingElse() throws {
        let original = image(rpaths: ["@loader_path"])
        let patched = try MachORpath.adding("@loader_path/../../external", to: original)
        #expect(try MachORpath.rpaths(in: patched) == ["@loader_path", "@loader_path/../../external"])
        // Same size, and the section's bytes are where they were.
        #expect(patched.count == original.count)
        #expect(patched.suffix(16) == original.suffix(16))
        // Only the header counters and the padding changed.
        let end = 32 + 72 + 80 + 24
        #expect(patched.prefix(16) == original.prefix(16))
        #expect(patched[32..<end] == original[32..<end])
    }

    @Test
    func addingTwiceChangesNothing() throws {
        let once = try MachORpath.adding("@loader_path/../lib", to: image())
        #expect(try MachORpath.adding("@loader_path/../lib", to: once) == once)
    }

    @Test
    func refusesWhenTheHeaderHasNoRoom() {
        // Contents start right after the load commands: nowhere to put it.
        let tight = image(contentOffset: 32 + 72 + 80)
        #expect(throws: MachORpath.RpathError.self) {
            try MachORpath.adding("@loader_path/../lib", to: tight)
        }
    }

    @Test
    func refusesWhatIsNotAThinMachO() {
        #expect(throws: MachORpath.RpathError.notMachO64) { try MachORpath.rpaths(in: Data("MZ not mach-o at all, really".utf8) + Data(count: 32)) }
        // A universal binary's magic is not handled; the engines ship none.
        #expect(throws: MachORpath.RpathError.notMachO64) { try MachORpath.rpaths(in: Data([0xCA, 0xFE, 0xBA, 0xBE]) + Data(count: 60)) }
        var truncated = image()
        truncated.removeLast(truncated.count - 40)
        #expect(throws: MachORpath.RpathError.malformed) { try MachORpath.rpaths(in: truncated) }
    }

    @Test
    func patchesAFileInPlaceKeepingItExecutable() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "fable-macho-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try image().write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        #expect(try MachORpath.add("@loader_path/../lib", to: file))
        #expect(try MachORpath.rpaths(of: file) == ["@loader_path/../lib"])
        #expect(try !MachORpath.add("@loader_path/../lib", to: file))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o755)
        #expect(try Sikarugir11Manager.hasLibraryRpath(file))
    }
}

/// Opt-in proof against Apple's own tool, on the engines' real files.
/// `FABLE_RPATH_PROOF_DIR` holds `apple/` (patched with install_name_tool) and
/// `swift/` (pristine copies of the same files); this patches the second set
/// and requires the two to be byte-identical.
@Suite("Mach-O rpath: same bytes as install_name_tool",
       .enabled(if: ProcessInfo.processInfo.environment["FABLE_RPATH_PROOF_DIR"] != nil))
struct MachORpathProofTests {
    @Test
    func realEngineFilesComeOutIdentical() throws {
        let root = URL(filePath: ProcessInfo.processInfo.environment["FABLE_RPATH_PROOF_DIR"]!)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "swift").path).sorted()
        #expect(!names.isEmpty)
        for name in names {
            let rpath = name == "wineserver" ? "@loader_path/../lib" : "@loader_path/../../external"
            let mine = root.appending(path: "swift/\(name)")
            #expect(try MachORpath.add(rpath, to: mine), "\(name) was already patched")
            let apple = try Data(contentsOf: root.appending(path: "apple/\(name)"))
            #expect(try Data(contentsOf: mine) == apple, "\(name) differs from install_name_tool's output")
        }
    }
}

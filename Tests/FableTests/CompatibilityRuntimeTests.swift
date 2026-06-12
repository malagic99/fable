import Foundation
import Testing
@testable import Fable

@Suite struct PEInfoTests {
    /// Minimal synthetic PE headers.
    private func peData(magic: UInt16) -> Data {
        var data = Data(count: 0x100)
        data[0] = 0x4D; data[1] = 0x5A                      // MZ
        data[0x3C] = 0x40                                    // e_lfanew = 0x40
        data[0x40] = 0x50; data[0x41] = 0x45                 // PE\0\0
        data[0x40 + 24] = UInt8(magic & 0xFF)                // optional magic
        data[0x40 + 25] = UInt8(magic >> 8)
        return data
    }

    @Test
    func detectsArchitectures() {
        #expect(PEInfo.architecture(of: peData(magic: 0x10B)) == .pe32)
        #expect(PEInfo.architecture(of: peData(magic: 0x20B)) == .pe64)
        #expect(PEInfo.architecture(of: Data("ELF".utf8)) == nil)
        #expect(PEInfo.architecture(of: Data()) == nil)
    }
}

@Suite struct CompanionPartsTests {
    @Test
    func findsMatchingBinParts() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "Parts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let exe = dir.appending(path: "setup_big_game_1.0.exe")
        for name in ["setup_big_game_1.0-1.bin", "setup_big_game_1.0-2.bin",
                     "setup_other_game-1.bin", "readme.txt"] {
            try Data("x".utf8).write(to: dir.appending(path: name))
        }
        try Data("MZ".utf8).write(to: exe)

        let parts = InnoExtractor.companionParts(of: exe)
        #expect(parts.map(\.lastPathComponent) ==
            ["setup_big_game_1.0-1.bin", "setup_big_game_1.0-2.bin"])
    }
}

@Suite struct CompatibilityRuntimeTests {
    @Test
    func discoversOnThisMachineIfAnySourcePresent() {
        // Discovery must never crash; on this dev machine Heroic's GPTK
        // exists, so it should be found.
        let runtime = CompatibilityRuntime.discover()
        if let runtime {
            #expect(FileManager.default.isExecutableFile(atPath: runtime.wineBinary.path))
            #expect(runtime.wineserverBinary.lastPathComponent == "wineserver")
        }
    }
}

import Foundation
import Testing
@testable import Fable

/// The GPTK dmg's libraries lose their quarantine flag on install, so they
/// must be Apple's own code first.
@Suite struct GPTKSignatureTests {
    static let appleFramework = "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework"

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gptk-sig-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url.appending(path: "external"), withIntermediateDirectories: true)
        return url
    }

    /// An ad-hoc signed dylib: signed, but not by Apple.
    func adHocDylib(at url: URL) async throws {
        let source = url.deletingPathExtension().appendingPathExtension("c")
        try Data("int fable_test(void) { return 1; }\n".utf8).write(to: source)
        let built = try await ProcessRunner.run(URL(filePath: "/usr/bin/clang"),
                                                arguments: ["-dynamiclib", source.path, "-o", url.path])
        #expect(built.succeeded)
        try FileManager.default.removeItem(at: source)
        _ = try await ProcessRunner.run(URL(filePath: "/usr/bin/codesign"),
                                        arguments: ["--force", "--sign", "-", url.path])
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: appleFramework)))
    func applesOwnFrameworkPasses() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(
            at: dir.appending(path: "external/D3DMetal.framework"),
            withDestinationURL: URL(filePath: Self.appleFramework))
        try await GPTKManager.requireAppleSignatures(in: dir)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: appleFramework)))
    func anyNonAppleDylibFailsTheWholeInstall() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(
            at: dir.appending(path: "external/D3DMetal.framework"),
            withDestinationURL: URL(filePath: Self.appleFramework))
        try await adHocDylib(at: dir.appending(path: "external/libd3dshared.dylib"))
        await #expect {
            try await GPTKManager.requireAppleSignatures(in: dir)
        } throws: { error in
            if case .notSignedByApple(let name) = error as? GPTKError { return name == "libd3dshared.dylib" }
            return false
        }
    }

    @Test
    func aFakeD3DMetalFails() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let framework = dir.appending(path: "external/D3DMetal.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try await adHocDylib(at: framework.appending(path: "D3DMetal"))
        await #expect {
            try await GPTKManager.requireAppleSignatures(in: dir)
        } throws: { error in
            if case .notSignedByApple = error as? GPTKError { return true }
            return false
        }
    }

    @Test
    func aPayloadWithoutD3DMetalIsRefused() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect {
            try await GPTKManager.requireAppleSignatures(in: dir)
        } throws: { error in
            if case .redistNotFound = error as? GPTKError { return true }
            return false
        }
    }
}

import Foundation

/// A runtime a Windows game may need, installable into any bottle.
struct Dependency: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let kind: RedistInstaller.Kind
    /// Download is a zip containing the actual installer.
    let isZipped: Bool
    /// File whose presence (relative to drive_c) means it's installed.
    let detectionPath: String
}

enum DependencyCatalog {
    static let all: [Dependency] = [
        Dependency(
            id: "vcredist-x64",
            name: "Visual C++ 2015–2022 (64-bit)",
            url: URL(string: "https://aka.ms/vs/17/release/vc_redist.x64.exe")!,
            kind: .vcRedist,
            isZipped: false,
            detectionPath: "windows/system32/msvcp140.dll"
        ),
        Dependency(
            id: "vcredist-x86",
            name: "Visual C++ 2015–2022 (32-bit)",
            url: URL(string: "https://aka.ms/vs/17/release/vc_redist.x86.exe")!,
            kind: .vcRedist,
            isZipped: false,
            detectionPath: "windows/syswow64/msvcp140.dll"
        ),
        Dependency(
            id: "openal",
            name: "OpenAL audio runtime",
            url: URL(string: "https://openal.org/downloads/oalinst.zip")!,
            kind: .openAL,
            isZipped: true,
            detectionPath: "windows/system32/OpenAL32.dll"
        ),
        Dependency(
            id: "directx-jun2010",
            name: "DirectX 9 runtime (June 2010)",
            url: URL(string: "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe")!,
            kind: .directX,
            isZipped: false,
            detectionPath: "windows/system32/d3dx9_43.dll"
        ),
    ]
}

/// Downloads and installs catalog dependencies into a bottle.
@MainActor
final class DependencyInstaller: ObservableObject {
    /// Dependency ids currently downloading/installing.
    @Published private(set) var installing: Set<String> = []

    func isInstalled(_ dependency: Dependency, bottle: Bottle, bottleManager: BottleManager) -> Bool {
        FileManager.default.fileExists(
            atPath: bottleManager.driveCDirectory(for: bottle)
                .appending(path: dependency.detectionPath).path
        )
    }

    func install(
        _ dependency: Dependency,
        bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) async throws {
        installing.insert(dependency.id)
        defer { installing.remove(dependency.id) }

        let fm = FileManager.default
        let workDir = AppPaths.downloads.appending(
            path: "dep-\(dependency.id)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var installerFile = workDir.appending(path: dependency.url.lastPathComponent)
        try await DownloadManager.download(from: dependency.url, to: installerFile)

        if dependency.isZipped {
            let result = try await ProcessRunner.run(
                URL(filePath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", installerFile.path, workDir.path]
            )
            guard result.succeeded else {
                throw ComponentError.extractionFailed(result.standardError)
            }
            guard let exe = try fm.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension.lowercased() == "exe" }) else {
                throw ComponentError.extractionFailed("no installer inside \(dependency.url.lastPathComponent)")
            }
            installerFile = exe
        }

        try await RedistInstaller().install(
            [installerFile],
            bottle: bottle,
            bottleManager: bottleManager,
            wineManager: wineManager
        )
    }
}

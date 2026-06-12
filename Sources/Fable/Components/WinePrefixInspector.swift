import Foundation

/// Reads facts back out of a Wine prefix that may have drifted from
/// Fable's metadata (e.g. the user changed the Windows version in
/// winecfg).
enum WinePrefixInspector {
    /// The Windows version the prefix actually reports, parsed from
    /// system.reg's CurrentBuildNumber. nil when unknown or unmappable.
    static func windowsVersion(ofPrefix prefix: URL) -> WindowsVersion? {
        let registry = prefix.appending(path: "system.reg")
        guard let contents = try? String(contentsOf: registry, encoding: .utf8) else {
            return nil
        }

        // Section: [Software\\Microsoft\\Windows NT\\CurrentVersion]
        // Key:     "CurrentBuildNumber"="19043"
        var inSection = false
        for line in contents.components(separatedBy: "\n") {
            if line.hasPrefix("[") {
                inSection = line.contains("Microsoft\\\\Windows NT\\\\CurrentVersion]")
                continue
            }
            guard inSection, line.hasPrefix("\"CurrentBuildNumber\"") else { continue }
            guard let value = line.split(separator: "=").last else { continue }
            let build = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "\" \r"))) ?? 0
            return version(forBuild: build)
        }
        return nil
    }

    static func version(forBuild build: Int) -> WindowsVersion? {
        switch build {
        case 22000...: .win11
        case 10000..<22000: .win10
        case 7600...7601: .win7
        default: nil
        }
    }
}

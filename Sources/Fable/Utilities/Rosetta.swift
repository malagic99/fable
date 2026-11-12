import Foundation

/// Rosetta 2, Apple's x86 translator. Every Windows engine Fable runs is an
/// x86 program, so nothing launches without it — and a Mac that has never run
/// an Intel app doesn't have it. macOS offers to install it when an Intel
/// *app* is opened from Finder, but not when a program is started directly,
/// which is how Fable starts Wine: that just fails with "Bad CPU type in
/// executable". The README used to send people to Terminal for this.
enum Rosetta {
    /// The translator's runtime library, present only once Rosetta is
    /// installed. (`/usr/libexec/rosetta` exists on every Apple Silicon Mac,
    /// installed or not, so it can't be the test.)
    static let runtimeMarker = URL(filePath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")

    static func isInstalled(marker: URL = runtimeMarker) -> Bool {
        FileManager.default.fileExists(atPath: marker.path)
    }

    /// Apple's own installer for it. Needs no administrator password.
    /// `--agree-to-license` accepts Apple's Rosetta licence without the
    /// Terminal prompt, so the interface has to say that before running it.
    static let installCommand = ["/usr/sbin/softwareupdate", "--install-rosetta", "--agree-to-license"]

    enum InstallError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let detail):
                L10n.string("rosetta.install_failed", detail)
            }
        }
    }

    /// Runs Apple's installer and confirms Rosetta is there afterwards.
    static func install() async throws {
        let result = try await ProcessRunner.run(
            URL(filePath: installCommand[0]), arguments: Array(installCommand.dropFirst()))
        guard isInstalled() else {
            throw InstallError.failed(failureDetail(
                standardOutput: result.standardOutput, standardError: result.standardError))
        }
    }

    /// The last line the installer printed, which is where it says why —
    /// its error output first, its progress output only if that was silent.
    static func failureDetail(standardOutput: String, standardError: String) -> String {
        func lastLine(_ text: String) -> String? {
            text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty }
        }
        return lastLine(standardError) ?? lastLine(standardOutput)
            ?? L10n.string("rosetta.install_failed.no_output")
    }
}

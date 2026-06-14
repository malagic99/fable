import SwiftUI

/// Pre-launch banner shown under a game row when CompatibilityScanner
/// has notes. Collapsed by default; expands to show all findings with
/// their suggestions. No findings → renders nothing.
struct CompatibilityBanner: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var crossOverManager: CrossOverManager
    @EnvironmentObject private var sikarugirManager: SikarugirManager
    @State private var findings: [CompatibilityFinding] = []
    @State private var recommendation: GraphicsBackend?
    @State private var isExpanded = false

    var body: some View {
        Group {
            if !findings.isEmpty {
                content
            }
        }
        .task(id: game.id) {
            // Resolve the URL on the main actor first (BottleManager is
            // MainActor-isolated), then hand the URL off to a utility-
            // priority detached task for the actual filesystem walk.
            let installDir = bottleManager.driveCDirectory(for: bottle)
                .appending(path: gameInstallDirectory(for: game))
            let crossOverAvailable = crossOverManager.isInstalled
            let sikarugirAvailable = sikarugirManager.isDiscovered
            findings = await Task.detached(priority: .utility) {
                CompatibilityScanner.scan(gameDirectory: installDir)
            }.value
            recommendation = CompatibilityScanner.recommendedBackend(
                for: findings,
                crossOverAvailable: crossOverAvailable,
                sikarugirAvailable: sikarugirAvailable
            )
        }
    }

    /// The directory that holds the game install. We take the parent
    /// of the registered exe; for repacks that's the "Retail" / "Bin"
    /// folder, which is what users keep their config files in too.
    private func gameInstallDirectory(for game: Game) -> String {
        (game.executablePath as NSString).deletingLastPathComponent
    }

    @ViewBuilder
    private var content: some View {
        let summary = highestSeverity()
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(findings) { finding in
                    findingRow(finding)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: summary.severity.systemImage)
                    .foregroundStyle(summary.severity.tint)
                Text(summaryText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let recommendation, bottle.graphicsBackend != recommendation {
                    Spacer()
                    Label("Try \(recommendation.shortName)", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(summary.severity.tint.opacity(0.08))
        )
    }

    @ViewBuilder
    private func findingRow(_ finding: CompatibilityFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.severity.systemImage)
                .foregroundStyle(finding.severity.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.title)
                    .font(.callout.weight(.medium))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !finding.suggestion.isEmpty {
                    Text(finding.suggestion)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private func highestSeverity() -> CompatibilityFinding {
        // Order: knownBlocker > caveat > info
        let order: [CompatibilityFinding.Severity] = [.knownBlocker, .caveat, .info]
        for target in order {
            if let match = findings.first(where: { $0.severity == target }) {
                return match
            }
        }
        return findings[0]
    }

    private func summaryText() -> String {
        let blockers = findings.filter { $0.severity == .knownBlocker }.count
        let caveats = findings.filter { $0.severity == .caveat }.count
        let infos = findings.filter { $0.severity == .info }.count
        var parts: [String] = []
        if blockers > 0 { parts.append("\(blockers) blocker\(blockers == 1 ? "" : "s")") }
        if caveats > 0 { parts.append("\(caveats) caveat\(caveats == 1 ? "" : "s")") }
        if infos > 0 { parts.append("\(infos) note\(infos == 1 ? "" : "s")") }
        return "Compatibility: " + parts.joined(separator: " · ")
    }
}

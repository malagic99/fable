import SwiftUI

/// Shows Fable Doctor's read of a game's last run — what the log says went
/// wrong and what to do about it.
struct DoctorSheet: View {
    let gameName: String
    let findings: [CompatibilityFinding]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Diagnosis — \(gameName)", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            Group {
                if findings.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Obvious", systemImage: "checkmark.circle")
                    } description: {
                        Text("The log has no known error signatures. If the game still misbehaves, open the full log for the raw output.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(findings) { finding in
                                row(finding)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 460)
    }

    private func row(_ finding: CompatibilityFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.severity.systemImage)
                .foregroundStyle(finding.severity.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.title).font(.callout.weight(.medium))
                Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                if !finding.suggestion.isEmpty {
                    Text(finding.suggestion).font(.caption).foregroundStyle(.tint).padding(.top, 2)
                }
            }
            Spacer()
        }
    }
}

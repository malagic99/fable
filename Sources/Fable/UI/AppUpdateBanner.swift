import SwiftUI

/// Top-of-window banner shown when AppUpdateChecker has a newer release.
/// "Dismiss" hides it for the session; "Skip This Version" silences it
/// until something newer ships.
struct AppUpdateBanner: View {
    @EnvironmentObject private var checker: AppUpdateChecker

    var body: some View {
        if let release = checker.available {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Fable \(release.version) is available")
                        .font(.callout.weight(.semibold))
                    Text("You're on \(AppUpdateChecker.currentVersion). Open the release page to download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Release Page") { checker.openInBrowser() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Menu {
                    Button("Skip This Version") { checker.skipThisVersion() }
                    Button("Dismiss") { checker.dismissBanner() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

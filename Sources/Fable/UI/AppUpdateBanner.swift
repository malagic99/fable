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
                    Text(L10n.string("update.available", release.version))
                        .font(.callout.weight(.semibold))
                    Text(L10n.string("update.current", AppUpdateChecker.currentVersion))
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

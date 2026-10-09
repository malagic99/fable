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
                    // While installing, the subtitle carries the stage rather
                    // than adding another row that shifts the layout.
                    Text(checker.installStage ?? L10n.string("update.current", AppUpdateChecker.currentVersion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let progress = checker.installProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                } else if let error = checker.lastError {
                    // Install failed: say so here rather than silently
                    // reverting to a button that looks like nothing happened.
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 280, alignment: .trailing)
                }

                if checker.installProgress == nil {
                    // Installing in place needs somewhere writable to install
                    // to; a dev build or a read-only location gets the browser.
                    if release.assetURL != nil, checker.canInstallInPlace {
                        Button("Update and Restart") {
                            Task { await checker.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Open Release Page") { checker.openInBrowser() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }

                    Menu {
                        Button("Open Release Page") { checker.openInBrowser() }
                        Divider()
                        Button("Skip This Version") { checker.skipThisVersion() }
                        Button("Dismiss") { checker.dismissBanner() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
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

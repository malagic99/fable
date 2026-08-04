import SwiftUI

/// Compose feedback and hand it to the browser as a pre-filled GitHub
/// issue. The whole report — including the optional system-info block —
/// is visible in the sheet before anything leaves the app, and nothing
/// does leave until the user posts the issue themselves on github.com.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var wineManager: WineManager

    @State private var report = FeedbackReport()
    @State private var includeSystemInfo = true

    /// Computed, not stored: the Wine layout comes from the environment, which
    /// isn't available at init time.
    private var diagnostics: String {
        FeedbackReport.currentDiagnostics(wineLayout: wineManager.layout)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Kind", selection: $report.category) {
                        ForEach(FeedbackReport.Category.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    TextField("Title", text: $report.title, prompt: Text("One line — what happened?"))

                    TextEditor(text: $report.message)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if report.message.isEmpty {
                                Text("The details — what you did, what you expected, what you got.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Feedback")
                }

                Section {
                    Toggle("Include system info", isOn: $includeSystemInfo)
                    if includeSystemInfo {
                        Text(diagnostics)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Nothing is sent by Fable. Review on GitHub opens a pre-filled issue in your browser — you post it (or don't) from there, and only what you see here is in it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            SheetActionBar {
                Button("Cancel", role: .cancel) { dismiss() }
            } trailing: {
                Button("Review on GitHub…") { openIssue() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!report.canSubmit)
            }
        }
        .frame(width: 460, height: 480)
    }

    private func openIssue() {
        report.diagnostics = includeSystemInfo ? diagnostics : nil
        guard let url = report.issueURL else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }
}

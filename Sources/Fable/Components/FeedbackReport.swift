import Foundation

/// A feedback report that becomes a pre-filled GitHub issue. Fable never
/// sends anything itself: `issueURL` opens the browser on the new-issue
/// page with every field visible, and the user posts it from their own
/// account (or walks away). Privacy by construction — the report contains
/// exactly what the sheet showed, nothing more, and no network request
/// leaves the app.
struct FeedbackReport: Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case bug
        case idea
        case question

        var id: String { rawValue }

        /// Rides in the title — labels in the new-issue URL are dropped
        /// silently for anyone without triage permission on the repo.
        var titlePrefix: String {
            switch self {
            case .bug: "[Bug]"
            case .idea: "[Idea]"
            case .question: "[Question]"
            }
        }

        var displayName: String {
            switch self {
            case .bug: L10n.string("feedback.category.bug")
            case .idea: L10n.string("feedback.category.idea")
            case .question: L10n.string("feedback.category.question")
            }
        }
    }

    var category: Category = .bug
    var title = ""
    var message = ""
    /// The exact system-info block appended when the user opts in;
    /// nil = the user turned it off. Always caller-supplied so the sheet
    /// shows the same text that ships.
    var diagnostics: String?

    static let repo = "malagic99/fable"

    /// GitHub accepts URLs well past this, but browsers start choking
    /// around 8 KB — cap the pre-encoding body so the worst case
    /// (every char percent-encoded, 3×) stays under it.
    static let bodyCap = 2500

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var issueTitle: String {
        "\(category.titlePrefix) \(title.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var issueBody: String {
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count > Self.bodyCap {
            body = String(body.prefix(Self.bodyCap)) + "…\n\n_(trimmed to fit the issue URL)_"
        }
        if let diagnostics {
            body += "\n\n### System\n\(diagnostics)"
        }
        return body
    }

    var issueURL: URL? {
        Self.newIssueURL(title: issueTitle, body: issueBody)
    }

    /// General pre-filled new-issue composer — also used by "Share This
    /// Setup" (recipe submissions). Same privacy property: nothing is sent;
    /// the browser opens on github.com with everything visible.
    static func newIssueURL(title: String, body: String) -> URL? {
        URL(string: "https://github.com/\(repo)/issues/new"
            + "?title=\(encodeQueryValue(title))"
            + "&body=\(encodeQueryValue(body))")
    }

    /// The block the "include system info" toggle previews. No serials,
    /// no usernames, no paths — the same spec line the About tab shows.
    static func currentDiagnostics(
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
        hardware: HardwareProfile = .current
    ) -> String {
        """
        Fable \(appVersion)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(hardware.summary)
        """
    }

    /// `.urlQueryAllowed` leaves `+`, `&`, and `=` alone, but inside a
    /// query value GitHub decodes `+` as a space and `&`/`=` as
    /// separators — "C++ crashes" would arrive as "C   crashes".
    private static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

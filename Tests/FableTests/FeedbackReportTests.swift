import Foundation
import Testing
@testable import Fable

/// The feedback → GitHub-issue composer. Privacy is structural — the
/// report only ever contains what the sheet showed — so these tests
/// guard the mechanics: title prefix, opt-in diagnostics, URL encoding,
/// and the body cap.
@Suite struct FeedbackReportTests {
    @Test
    func titleCarriesTheCategoryPrefix() {
        var report = FeedbackReport(category: .bug, title: "  Steam window is black  ", message: "x")
        #expect(report.issueTitle == "[Bug] Steam window is black")

        report.category = .idea
        #expect(report.issueTitle.hasPrefix("[Idea] "))
    }

    @Test
    func diagnosticsAppearOnlyWhenOptedIn() {
        var report = FeedbackReport(title: "t", message: "The game crashes on launch.")
        #expect(!report.issueBody.contains("### System"))

        report.diagnostics = "Fable 0.17.0\nmacOS 26\nApple M4 Pro · 24 GB"
        #expect(report.issueBody.hasSuffix("### System\nFable 0.17.0\nmacOS 26\nApple M4 Pro · 24 GB"))
    }

    @Test
    func urlEncodesQueryHostileCharacters() throws {
        // "+" would decode as a space on GitHub's side; "&" and "="
        // would break the query apart. All three must be percent-encoded.
        let report = FeedbackReport(title: "C++ & Rust = trouble", message: "a+b")
        let url = try #require(report.issueURL)
        let absolute = url.absoluteString

        #expect(absolute.hasPrefix("https://github.com/\(FeedbackReport.repo)/issues/new?"))
        #expect(!absolute.dropFirst("https://".count).contains("+"))

        // Round-trip: the decoded query must reproduce the report exactly.
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        #expect(items.first { $0.name == "title" }?.value == "[Bug] C++ & Rust = trouble")
        #expect(items.first { $0.name == "body" }?.value == "a+b")
    }

    @Test
    func oversizedBodyIsCappedWithANote() {
        let report = FeedbackReport(title: "t", message: String(repeating: "z", count: 10_000))
        #expect(report.issueBody.count < FeedbackReport.bodyCap + 100)
        #expect(report.issueBody.contains("trimmed"))
        #expect(report.issueURL != nil)
    }

    @Test
    func submitRequiresTitleAndMessage() {
        #expect(!FeedbackReport(title: "", message: "").canSubmit)
        #expect(!FeedbackReport(title: "t", message: "  \n ").canSubmit)
        #expect(!FeedbackReport(title: " ", message: "m").canSubmit)
        #expect(FeedbackReport(title: "t", message: "m").canSubmit)
    }

    @Test
    func currentDiagnosticsAreTheAboutTabFacts() {
        let hardware = HardwareProfile(
            chipName: "Apple M4 Pro", modelIdentifier: "Mac16,8",
            memoryBytes: 25_769_803_776, performanceCores: 8,
            efficiencyCores: 4, gpuCores: 16
        )
        let block = FeedbackReport.currentDiagnostics(appVersion: "0.18.0", hardware: hardware)
        #expect(block.hasPrefix("Fable 0.18.0\nmacOS "))
        #expect(block.hasSuffix(hardware.summary))
        // Three known lines, nothing else rides along.
        #expect(block.split(separator: "\n").count == 3)
    }
}

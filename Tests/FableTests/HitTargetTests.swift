import Foundation
import Testing
@testable import Fable

/// THE hit-target gate. A view that paints itself with `.clear` in one of its
/// states is invisible to hit testing in that state: SwiftUI tests the drawn
/// shape, and a clear fill draws nothing. The button still *looks* like a
/// bubble — the border and the text are there — so the dead gaps between them
/// are impossible to see in a screenshot and impossible to catch by reading
/// the view in isolation. They only show up as "clicking it sometimes does
/// nothing", which is how all three of these shipped.
///
/// The rule: if a view fills or strokes conditionally with `.clear`, the file
/// has to declare a `contentShape`. That is a proxy rather than a proof — it
/// is per-file, so it cannot tell which view the shape belongs to — but it
/// catches the whole bug class at the one place where it is cheap to notice,
/// and the fix is always the same one line.
///
/// Adding a card with a selected/unselected fill: add
/// `.contentShape(RoundedRectangle(cornerRadius: …))` after the background and
/// overlay, before any gesture or `.onHover`.
@Suite struct HitTargetTests {
    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FableTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appending(path: "Sources/Fable", directoryHint: .isDirectory)

    /// A ternary whose else-branch is `.clear`, `Color.clear` or
    /// `AnyShapeStyle(.clear)` — the shape that disappears from hit testing.
    private static let conditionalClear = try! NSRegularExpression(
        pattern: #"\?[^:\n]*:\s*(?:AnyShapeStyle\(\s*)?(?:Color\.)?\.?clear"#
    )

    private func swiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil)!
        return (enumerator.compactMap { $0 as? URL }).filter { $0.pathExtension == "swift" }
    }

    /// The gate itself.
    @Test
    func everyConditionallyClearViewDeclaresItsHitShape() throws {
        var offenders: [String] = []
        for url in try swiftFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            guard Self.conditionalClear.firstMatch(in: text, range: range) != nil else { continue }
            guard !text.contains("contentShape") else { continue }
            offenders.append(url.lastPathComponent)
        }
        #expect(
            offenders.isEmpty,
            """
            These views go transparent in one state but never declare a hit \
            shape, so clicks land only on their text and border: \
            \(offenders.sorted().joined(separator: ", ")). \
            Add .contentShape(…) after the background/overlay.
            """
        )
    }

    /// Guards the gate: a regex that matches nothing would pass silently
    /// forever. The cards fixed alongside this suite are the fixtures.
    @Test
    func theGateActuallyMatchesTheKnownPattern() throws {
        let fixtures = [
            #".fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)"#,
            #".fill(isSelected ? FableTheme.surfaceSelected : AnyShapeStyle(.clear))"#,
            #"isActive ? AnyShapeStyle(.quaternary.opacity(0.8)) : AnyShapeStyle(.clear),"#,
            #".strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)"#,
        ]
        for fixture in fixtures {
            let range = NSRange(fixture.startIndex..., in: fixture)
            #expect(
                Self.conditionalClear.firstMatch(in: fixture, range: range) != nil,
                "the gate no longer recognises: \(fixture)"
            )
        }
    }
}

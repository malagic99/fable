import Testing
@testable import Fable

@Suite struct AppStateTests {
    @Test @MainActor
    func defaultSectionIsBottles() {
        #expect(AppState().selectedSection == .bottles)
    }

    @Test @MainActor
    func sectionSwitching() {
        let state = AppState()
        for section in AppSection.allCases {
            state.selectedSection = section
            #expect(state.selectedSection == section)
        }
    }

    @Test
    func everySectionHasTitleAndIcon() {
        for section in AppSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.systemImage.isEmpty)
        }
    }
}

import Foundation
import Testing
@testable import Fable

@Suite struct SteamBottleTemplateTests {
    @Test
    func steamTemplateRegistersSteamWithNoCEFSandbox() throws {
        let steam = try #require(
            BottleTemplateCatalog.all.first { $0.id == "steam-ready" }
        )
        let registration = try #require(steam.gamesToRegister.first)
        #expect(registration.name == "Steam")
        #expect(registration.executablePath == "Program Files (x86)/Steam/Steam.exe")
        // The single most important macOS-Wine Steam workaround — don't
        // let a future refactor drop it.
        #expect(registration.arguments.contains("-no-cef-sandbox"))
    }

    @Test
    func nonSteamTemplatesDoNotRegisterGames() {
        for tmpl in BottleTemplateCatalog.all where tmpl.id != "steam-ready" {
            #expect(tmpl.gamesToRegister.isEmpty, "\(tmpl.id) unexpectedly registers games")
        }
    }

    @Test
    func steamTemplateChainsBackendAndDependencies() throws {
        let steam = try #require(
            BottleTemplateCatalog.all.first { $0.id == "steam-ready" }
        )
        #expect(steam.graphicsBackend == .sikarugir)
        // Sanity: the macOS Steam install needs vcredist + corefonts; the
        // winetricks `steam` verb handles the actual download.
        #expect(steam.dependencyIDs.contains("vcredist-x64"))
        #expect(steam.dependencyIDs.contains("vcredist-x86"))
        #expect(steam.winetricksVerbs.contains("steam"))
        #expect(steam.winetricksVerbs.contains("corefonts"))
    }

    @Test
    func gameRegistrationRoundTripsThroughGameStruct() {
        let registration = GameRegistration(
            name: "Steam",
            executablePath: "Program Files (x86)/Steam/Steam.exe",
            arguments: "-no-cef-sandbox"
        )
        let game = Game(
            name: registration.name,
            executablePath: registration.executablePath,
            arguments: registration.arguments
        )
        #expect(game.arguments == "-no-cef-sandbox")
        #expect(game.executablePath == "Program Files (x86)/Steam/Steam.exe")
    }

    @Test
    func vanillaTemplateRemainsVanillaWithEmptyGameList() throws {
        let vanilla = try #require(
            BottleTemplateCatalog.all.first { $0.id == "vanilla" }
        )
        #expect(vanilla.isVanilla)
        #expect(vanilla.gamesToRegister.isEmpty)
    }
}

import Foundation
import Testing
@testable import Fable

/// The minimal VDF (Valve KeyValues) reader/writer used for Steam's
/// appmanifest_*.acf files.
@Suite struct SteamKeyValuesTests {
    private let sample = #"""
    "AppState"
    {
    	"appid"		"228980"
    	"LauncherPath"		"C:\\Program Files (x86)\\Steam\\steam.exe"
    	"installdir"		"Steamworks Shared"
    	"BytesToStage"		"163"
    	"InstalledDepots"
    	{
    		"228989"
    		{
    			"manifest"		"3514306556860204959"
    			"size"		"39590283"
    		}
    	}
    }
    """#

    @Test
    func parsesScalarsAndNesting() throws {
        let root = try #require(SteamKeyValues.parse(sample))
        #expect(root.key == "AppState")
        #expect(root.value.string("installdir") == "Steamworks Shared")
        #expect(root.value.int("BytesToStage") == 163)
        // Nested object reachable via subscripts.
        let manifest = root.value["InstalledDepots"]?["228989"]?.string("manifest")
        #expect(manifest == "3514306556860204959")
    }

    @Test
    func unescapesAndRePreservesBackslashPaths() throws {
        let root = try #require(SteamKeyValues.parse(sample))
        // On-disk \\  decodes to a single backslash.
        #expect(root.value.string("LauncherPath") == #"C:\Program Files (x86)\Steam\steam.exe"#)
        // Re-serializing escapes it back, so a round-trip is stable.
        let out = SteamKeyValues.serialize(key: root.key, value: root.value)
        let reparsed = try #require(SteamKeyValues.parse(out))
        #expect(reparsed.value == root.value)
        #expect(out.contains(#"C:\\Program Files (x86)\\Steam\\steam.exe"#))
    }

    @Test
    func setReplacesAndAppendsScalars() throws {
        var root = try #require(SteamKeyValues.parse(sample)).value
        root.set("BytesToStage", "999")        // replace existing
        root.set("StateFlags", "4")            // append new
        #expect(root.int("BytesToStage") == 999)
        #expect(root.string("StateFlags") == "4")
        // Order preserved: existing key stays in place, new one is appended.
        guard case .object(let pairs) = root else { Issue.record("expected object"); return }
        #expect(pairs.first?.key == "appid")
        #expect(pairs.last?.key == "StateFlags")
    }

    @Test
    func setObjectReplacesNestedBlock() throws {
        var root = try #require(SteamKeyValues.parse(sample)).value
        let depots = VDFValue.object([
            ("111", .object([("manifest", .string("222")), ("size", .string("0"))]))
        ])
        root.set("InstalledDepots", object: depots)
        #expect(root["InstalledDepots"]?["111"]?.string("manifest") == "222")
        #expect(root["InstalledDepots"]?["228989"] == nil)
    }
}

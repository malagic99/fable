import Foundation

/// The cover-art pipeline's pure parts: URL builders, response parsing, and
/// cache naming. Resolution order (cheapest, most-official first):
///
///   1. Steam appid from the bottle's appmanifest → Steam's keyless CDN portrait.
///   2. Keyless Steam store search by name (covers Epic/GOG copies of games
///      that are also on Steam — most of a real library).
///   3. SteamGridDB by name (optional API key) for everything else.
///   4. No artwork → the views keep the exe-icon fallback.
///
/// All fetched art is cached to disk; the network is hit at most once per title.
enum GameArtwork {

    /// Steam's public CDN portrait capsule (600×900) — keyless, official art.
    static func steamCoverURL(appID: Int) -> URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")!
    }

    /// Keyless Steam store search — resolves a name to an appid even when the
    /// user's copy came from Epic/GOG/Heroic.
    static func storeSearchURL(name: String) -> URL {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch")!
        components.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "cc", value: "us"),
            URLQueryItem(name: "l", value: "english"),
        ]
        return components.url!
    }

    /// SteamGridDB endpoints (need an API key as a Bearer header).
    static func sgdbSearchURL(name: String) -> URL {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://www.steamgriddb.com/api/v2/search/autocomplete/\(escaped)")!
    }

    static func sgdbGridsURL(gameID: Int) -> URL {
        URL(string: "https://www.steamgriddb.com/api/v2/grids/game/\(gameID)?dimensions=600x900")!
    }

    // MARK: Parsing

    /// Store-search hit whose name matches the query (normalized) — first
    /// loose match wins; a result that shares no words with the query is
    /// rejected rather than risking wildly wrong art.
    static func appID(fromStoreSearch data: Data, matching name: String) -> Int? {
        struct Response: Decodable {
            struct Item: Decodable {
                let id: Int
                let name: String
            }
            let items: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let wanted = normalize(name)
        // Exact normalized match first, then prefix/containment.
        if let exact = response.items.first(where: { normalize($0.name) == wanted }) { return exact.id }
        return response.items.first(where: {
            normalize($0.name).hasPrefix(wanted) || wanted.hasPrefix(normalize($0.name))
        })?.id
    }

    static func gameID(fromSGDBSearch data: Data) -> Int? {
        struct Response: Decodable {
            struct Item: Decodable { let id: Int }
            let data: [Item]
        }
        return (try? JSONDecoder().decode(Response.self, from: data))?.data.first?.id
    }

    static func gridURL(fromSGDBGrids data: Data) -> URL? {
        struct Response: Decodable {
            struct Item: Decodable { let url: String }
            let data: [Item]
        }
        guard let first = (try? JSONDecoder().decode(Response.self, from: data))?.data.first else { return nil }
        return URL(string: first.url)
    }

    // MARK: Keys

    /// Art is per-title: the cache key is the normalized game name.
    static func cacheKey(for name: String) -> String {
        normalize(name).replacingOccurrences(of: " ", with: "-")
    }

    /// Steam itself gets no store art — a search for "Steam" would fetch some
    /// unrelated game's cover onto the client's tile.
    static func isSteamClient(_ game: Game) -> Bool {
        game.executablePath.lowercased().replacingOccurrences(of: "\\", with: "/")
            .hasSuffix("steam.exe")
    }

    /// Lowercase, strip ™/® and punctuation, collapse whitespace.
    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}

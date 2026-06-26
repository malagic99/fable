import Foundation

/// Fetches a ProtonDB summary for a Steam appid. A protocol so the network is
/// injectable — tests use a stub, and nothing hits the wire unless the user has
/// opted into online lookups.
protocol ProtonDBFetching: Sendable {
    func summary(appID: Int) async -> ProtonDBSummary?
}

/// Live ProtonDB client. Best-effort: any failure (offline, 404, rate limit)
/// returns nil, and the caller falls back to offline sources.
struct ProtonDBClient: ProtonDBFetching {
    var session: URLSession = .shared

    func summary(appID: Int) async -> ProtonDBSummary? {
        var request = URLRequest(url: ProtonDB.summaryURL(appID: appID))
        request.timeoutInterval = 8
        request.setValue("Fable", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(ProtonDBSummary.self, from: data)
    }
}

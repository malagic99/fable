import Foundation

struct DownloadProgress: Sendable, Equatable {
    let bytesReceived: Int64
    let totalBytes: Int64?

    /// 0…1 when the server reported a content length, nil otherwise.
    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return Double(bytesReceived) / Double(totalBytes)
    }
}

enum DownloadError: LocalizedError {
    case badStatus(Int, URL)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let url):
            "Download failed (HTTP \(code)) for \(url.lastPathComponent)."
        }
    }
}

/// Streams a URL to a local file, reporting progress. Cancellable via
/// regular task cancellation.
enum DownloadManager {
    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.badStatus(http.statusCode, url)
        }

        let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data(capacity: 1 << 16)
        var received: Int64 = 0
        var lastReport = ContinuousClock.now

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    // Throttle progress callbacks to ~10/s.
                    let now = ContinuousClock.now
                    if now - lastReport > .milliseconds(100) {
                        lastReport = now
                        progress(DownloadProgress(bytesReceived: received, totalBytes: totalBytes))
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }
            progress(DownloadProgress(bytesReceived: received, totalBytes: totalBytes))
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

import Foundation

/// Reads Steam's local app cache, `appcache/appinfo.vdf` — the client's own
/// copy of each app's public metadata, including the launch entries that say
/// which executable is the game. It is what Steam itself consults when Play
/// is pressed, so it is the authoritative answer to "which .exe?", it needs
/// no network, and it covers every app the account has looked at.
///
/// The file is binary: a header, then one record per app holding a binary
/// KeyValues tree. Two layouts are read:
///
/// - `0x07564429` (current): keys are indices into a string table at the end
///   of the file.
/// - `0x07564428`: keys are inline NUL-terminated strings.
///
/// Older layouts are not attempted — nil is returned and the caller falls
/// back. Every read is bounds-checked: the file is another program's cache,
/// may be mid-write, and must never be able to crash Fable.
enum SteamAppInfoCache {
    private static let magicWithStringTable: UInt32 = 0x0756_4429
    private static let magicInlineKeys: UInt32 = 0x0756_4428

    /// Largest cache read at all. A big library's cache is tens of MB.
    static let maxFileBytes = 512 << 20

    /// Bytes between an app record's size field and its KeyValues tree:
    /// info state, last updated, PICS token, text SHA-1, change number,
    /// binary SHA-1.
    private static let recordHeaderSize = 4 + 4 + 8 + 20 + 4 + 20

    /// The `appinfo` tree for each requested app found in the cache.
    /// Nil when the file isn't a layout this reads.
    static func entries(for appIDs: Set<Int>, in data: Data) -> [Int: VDFValue]? {
        var reader = Reader(data: data)
        guard let magic = reader.u32(), reader.u32() != nil else { return nil }

        var strings: [String]?
        switch magic {
        case magicWithStringTable:
            guard let offset = reader.i64(), offset > 0, offset < Int64(data.count) else { return nil }
            var table = Reader(data: data, position: Int(offset))
            // Every string takes at least its NUL byte, so a count larger than
            // what's left of the file is a lie — refuse it before allocating.
            guard let count = table.u32(), Int(count) <= data.count - table.position else { return nil }
            var list: [String] = []
            list.reserveCapacity(min(Int(count), 1 << 16))
            for _ in 0..<count {
                guard let string = table.cString() else { return nil }
                list.append(string)
            }
            strings = list
        case magicInlineKeys:
            break
        default:
            return nil
        }

        var result: [Int: VDFValue] = [:]
        while let appID = reader.u32(), appID != 0 {
            guard let size = reader.u32() else { break }
            let recordStart = reader.position
            let recordEnd = recordStart + Int(size)
            guard recordEnd <= data.count else { break }
            if appIDs.contains(Int(appID)) {
                var tree = Reader(data: data, position: recordStart + recordHeaderSize, limit: recordEnd)
                if let root = tree.object(strings: strings, depth: 0) {
                    // The record's single top-level key is "appinfo".
                    result[Int(appID)] = root["appinfo"] ?? root
                }
                if result.count == appIDs.count { break }
            }
            reader.position = recordEnd
        }
        return result
    }

    static func entries(for appIDs: Set<Int>, steamRoot: URL) -> [Int: VDFValue]? {
        let file = steamRoot.appending(path: "appcache/appinfo.vdf")
        // Read, not memory-mapped: Steam may rewrite this file while Fable
        // scans it, and a mapped file truncated underneath crashes the reader
        // (SIGBUS) — bounds checks can't help, the length they check is stale.
        // Security scan 2026-11-20, finding 7.
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)??.intValue,
              size <= maxFileBytes,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return entries(for: appIDs, in: data)
    }

    // MARK: Binary reading

    private struct Reader {
        let data: Data
        var position: Int
        let limit: Int

        init(data: Data, position: Int = 0, limit: Int? = nil) {
            self.data = data
            self.position = position
            self.limit = min(limit ?? data.count, data.count)
        }

        mutating func byte() -> UInt8? {
            guard position < limit else { return nil }
            defer { position += 1 }
            return data[data.startIndex + position]
        }

        mutating func u32() -> UInt32? {
            guard position >= 0, position + 4 <= limit else { return nil }
            let start = data.startIndex + position
            position += 4
            return UInt32(data[start]) | UInt32(data[start + 1]) << 8
                | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
        }

        mutating func u64() -> UInt64? {
            guard let low = u32(), let high = u32() else { return nil }
            return UInt64(low) | UInt64(high) << 32
        }

        mutating func i64() -> Int64? { u64().map { Int64(bitPattern: $0) } }

        mutating func cString() -> String? {
            guard position >= 0, position < limit else { return nil }
            let start = data.startIndex + position
            guard let end = data[start..<(data.startIndex + limit)].firstIndex(of: 0) else { return nil }
            position = end - data.startIndex + 1
            return String(decoding: data[start..<end], as: UTF8.self)
        }

        /// One KeyValues object: typed entries until an end marker.
        mutating func object(strings: [String]?, depth: Int) -> VDFValue? {
            guard depth < 32 else { return nil }
            var pairs: [(key: String, value: VDFValue)] = []
            while true {
                guard let type = byte() else { return nil }
                if type == 0x08 || type == 0x0B { return .object(pairs) }

                let key: String
                if let strings {
                    guard let index = u32(), Int(index) < strings.count else { return nil }
                    key = strings[Int(index)]
                } else {
                    guard let inline = cString() else { return nil }
                    key = inline
                }

                switch type {
                case 0x00:
                    guard let child = object(strings: strings, depth: depth + 1) else { return nil }
                    pairs.append((key, child))
                case 0x01:
                    guard let string = cString() else { return nil }
                    pairs.append((key, .string(string)))
                case 0x02:
                    guard let value = u32() else { return nil }
                    pairs.append((key, .string(String(Int32(bitPattern: value)))))
                case 0x07:
                    guard let value = u64() else { return nil }
                    pairs.append((key, .string(String(value))))
                default:
                    // A type this doesn't know: its size is unknown, so the
                    // rest of the record can't be trusted.
                    return nil
                }
            }
        }
    }
}

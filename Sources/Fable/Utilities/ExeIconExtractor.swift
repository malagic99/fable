import AppKit
import Foundation

/// Extracts the embedded icon from a Windows PE executable by walking
/// its resource tree (RT_GROUP_ICON + RT_ICON) and rebuilding a .ico
/// blob NSImage can read. Returns nil for anything unexpected — a
/// missing icon is never an error.
enum ExeIconExtractor {
    static func icon(forExecutable url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let ico = icoData(from: data) else { return nil }
        return NSImage(data: ico)
    }

    // MARK: PE parsing

    private struct Section {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawPointer: UInt32
        let rawSize: UInt32
    }

    static func icoData(from data: Data) -> Data? {
        guard data.count > 0x40, data[0] == 0x4D, data[1] == 0x5A else { return nil }  // "MZ"
        let peOffset = Int(readU32(data, 0x3C))
        guard peOffset + 24 < data.count,
              readU32(data, peOffset) == 0x0000_4550 else { return nil }  // "PE\0\0"

        let numSections = Int(readU16(data, peOffset + 6))
        let optionalSize = Int(readU16(data, peOffset + 20))
        let optionalStart = peOffset + 24
        guard optionalStart + optionalSize <= data.count, optionalSize >= 96 else { return nil }

        // Resource directory is data directory #2.
        let magic = readU16(data, optionalStart)
        let directoriesOffset: Int
        switch magic {
        case 0x10B: directoriesOffset = optionalStart + 96   // PE32
        case 0x20B: directoriesOffset = optionalStart + 112  // PE32+
        default: return nil
        }
        let resourceRVA = readU32(data, directoriesOffset + 2 * 8)
        guard resourceRVA != 0 else { return nil }

        // Section table follows the optional header.
        var sections: [Section] = []
        var cursor = optionalStart + optionalSize
        for _ in 0..<numSections {
            guard cursor + 40 <= data.count else { return nil }
            sections.append(Section(
                virtualAddress: readU32(data, cursor + 12),
                virtualSize: readU32(data, cursor + 8),
                rawPointer: readU32(data, cursor + 20),
                rawSize: readU32(data, cursor + 16)
            ))
            cursor += 40
        }

        func fileOffset(ofRVA rva: UInt32) -> Int? {
            for s in sections {
                let size = max(s.virtualSize, s.rawSize)
                if rva >= s.virtualAddress && rva < s.virtualAddress + size {
                    return Int(s.rawPointer + (rva - s.virtualAddress))
                }
            }
            return nil
        }

        guard let resourceBase = fileOffset(ofRVA: resourceRVA) else { return nil }

        // Resource directory entries: 8 bytes (id, offset; high bit of
        // offset = points to a subdirectory).
        func entries(dirOffset: Int) -> [(id: UInt32, offset: UInt32, isDir: Bool)] {
            guard dirOffset + 16 <= data.count else { return [] }
            let named = Int(readU16(data, dirOffset + 12))
            let ids = Int(readU16(data, dirOffset + 14))
            var result: [(UInt32, UInt32, Bool)] = []
            var entry = dirOffset + 16
            for _ in 0..<(named + ids) {
                guard entry + 8 <= data.count else { break }
                let id = readU32(data, entry)
                let raw = readU32(data, entry + 4)
                result.append((id, raw & 0x7FFF_FFFF, raw & 0x8000_0000 != 0))
                entry += 8
            }
            return result
        }

        // First subdirectory two levels down (name/language) → data entry.
        func firstDataEntry(below dirOffset: Int) -> (rva: UInt32, size: UInt32)? {
            var offset = dirOffset
            for _ in 0..<3 {
                guard let first = entries(dirOffset: offset).first else { return nil }
                if !first.isDir {
                    let dataEntry = resourceBase + Int(first.offset)
                    guard dataEntry + 8 <= data.count else { return nil }
                    return (readU32(data, dataEntry), readU32(data, dataEntry + 4))
                }
                offset = resourceBase + Int(first.offset)
            }
            return nil
        }

        func resourceBlob(_ entry: (rva: UInt32, size: UInt32)) -> Data? {
            guard let start = fileOffset(ofRVA: entry.rva),
                  start + Int(entry.size) <= data.count else { return nil }
            return data.subdata(in: start..<start + Int(entry.size))
        }

        let root = entries(dirOffset: resourceBase)
        let RT_ICON: UInt32 = 3
        let RT_GROUP_ICON: UInt32 = 14

        guard let groupDir = root.first(where: { $0.id == RT_GROUP_ICON && $0.isDir }),
              let groupEntry = firstDataEntry(below: resourceBase + Int(groupDir.offset)),
              let group = resourceBlob(groupEntry),
              group.count >= 6 else { return nil }

        // Map every RT_ICON id to its blob.
        var icons: [UInt32: Data] = [:]
        if let iconDir = root.first(where: { $0.id == RT_ICON && $0.isDir }) {
            for idEntry in entries(dirOffset: resourceBase + Int(iconDir.offset)) where idEntry.isDir {
                if let dataEntry = firstDataEntry(below: resourceBase + Int(idEntry.offset)),
                   let blob = resourceBlob(dataEntry) {
                    icons[idEntry.id] = blob
                }
            }
        }
        guard !icons.isEmpty else { return nil }

        // GRPICONDIR → ICONDIR: 14-byte entries (id) become 16-byte
        // entries (file offset).
        let count = Int(readU16(group, 4))
        guard count > 0, group.count >= 6 + count * 14 else { return nil }

        var included: [(meta: Data, blob: Data)] = []
        for i in 0..<count {
            let entry = 6 + i * 14
            let iconID = UInt32(readU16(group, entry + 12))
            guard let blob = icons[iconID] else { continue }
            // dims/colors/planes/bpp carry over unchanged.
            included.append((group.subdata(in: entry..<entry + 8), blob))
        }
        guard !included.isEmpty else { return nil }

        var header = Data([0, 0, 1, 0]) + le16(UInt16(included.count))
        var blobOffset = 6 + 16 * included.count
        var blobs = Data()
        for (meta, blob) in included {
            header += meta + le32(UInt32(blob.count)) + le32(UInt32(blobOffset))
            blobOffset += blob.count
            blobs += blob
        }
        return header + blobs
    }

    // MARK: Little-endian helpers

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset])
            | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for i in (0..<4).reversed() {
            value = value << 8 | UInt32(data[data.startIndex + offset + i])
        }
        return value
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}

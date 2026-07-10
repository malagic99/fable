import Foundation

/// The "Memory Diet" for Unreal Engine games on unified-memory Macs.
///
/// On a PC a UE game budgets its texture-streaming pool against a separate
/// VRAM figure. On Apple Silicon RAM and VRAM are one pool, and D3DMetal
/// reports that whole pool as "GPU memory" — so the engine sizes its
/// streaming cache toward a budget that doesn't physically exist and grows
/// into a wired-memory crash over a session (the STALKER 2 / TLOU2 "bleed").
///
/// The fix the community uses is a hard cap on the streaming pool via
/// `Engine.ini`. This encodes exactly that as a **reversible, idempotent**
/// edit of the game's user config: a marker-delimited `[SystemSettings]`
/// block Fable owns. The block's presence in the file *is* the on/off state —
/// no separate persistence, and removing it restores the original file.
///
/// Pure string operations here; path discovery lives in the BottleManager
/// extension (needs prefix layout).
enum MemoryDiet {
    static let beginMarker = "; --- Fable Memory Diet (managed — safe to delete) ---"
    static let endMarker = "; --- end Fable Memory Diet ---"

    /// Streaming-pool cap in MB, sized from unified memory. The pool is
    /// shared with everything else in the same RAM, so we stay conservative;
    /// bigger machines can afford a larger cache before pressure bites.
    static func recommendedPoolMB(forMemoryGB gb: Int) -> Int {
        switch gb {
        case ..<16: 1536    // 8 GB — aggressive
        case 16..<32: 3072  // 16/24 GB — the common case (M-series Pro)
        case 32..<64: 4096
        default: 6144       // 64 GB+ — real headroom
        }
    }

    /// The managed block. `LimitPoolSizeToVRAM=0` stops the engine from
    /// re-deriving the pool from D3DMetal's (inflated) VRAM report and
    /// overriding our cap.
    static func block(poolMB: Int) -> String {
        """
        \(beginMarker)
        [SystemSettings]
        r.Streaming.PoolSize=\(poolMB)
        r.Streaming.LimitPoolSizeToVRAM=0
        \(endMarker)
        """
    }

    /// True if the file already carries our managed block.
    static func isApplied(_ ini: String) -> Bool {
        ini.contains(beginMarker)
    }

    /// The pool size currently written by our block, if any.
    static func appliedPoolMB(_ ini: String) -> Int? {
        guard isApplied(ini) else { return nil }
        // Only read within our block, so a game's own PoolSize line elsewhere
        // isn't mistaken for ours.
        let managed = ini.components(separatedBy: beginMarker).dropFirst().first ?? ""
        for line in managed.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("r.Streaming.PoolSize="),
               let v = Int(t.dropFirst("r.Streaming.PoolSize=".count).trimmingCharacters(in: .whitespaces)) {
                return v
            }
            if t == endMarker { break }
        }
        return nil
    }

    /// Add or replace our block. Idempotent: applying twice (or re-applying
    /// with a new size) leaves exactly one block, appended at the end so it
    /// wins over the game's own `[SystemSettings]`.
    static func apply(to ini: String, poolMB: Int) -> String {
        let stripped = remove(from: ini)
        let base = stripped.isEmpty ? "" : stripped.hasSuffix("\n") ? stripped : stripped + "\n"
        return base + block(poolMB: poolMB) + "\n"
    }

    /// Remove our block (and the surrounding blank lines it introduced),
    /// restoring the file to its pre-diet state. Safe on files without one.
    static func remove(from ini: String) -> String {
        guard let start = ini.range(of: beginMarker) else { return ini }
        guard let end = ini.range(of: endMarker, range: start.upperBound..<ini.endIndex) else {
            // Malformed (begin without end) — drop from the marker onward.
            return String(ini[ini.startIndex..<start.lowerBound])
                .trimmingCharacters(in: .newlines) + (start.lowerBound == ini.startIndex ? "" : "\n")
        }
        var before = String(ini[ini.startIndex..<start.lowerBound])
        let after = String(ini[end.upperBound..<ini.endIndex])
        // Collapse the seam so repeated apply/remove doesn't accrete blanks.
        while before.hasSuffix("\n") { before.removeLast() }
        let tail = after.drop { $0 == "\n" }
        if before.isEmpty { return String(tail) }
        return tail.isEmpty ? before + "\n" : before + "\n" + tail
    }
}

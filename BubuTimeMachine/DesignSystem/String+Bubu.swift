import Foundation

extension String {
    /// 去首尾空白与换行。全工程共享（HealthRecordSheet 内的 private trimmed 为历史遗留）。
    var bubuTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 跨进程稳定的哈希（FNV-1a over UTF-8）。
    /// Swift 原生 hashValue 每次启动带随机种子，用它取色会让"这条记忆是这个颜色"每次开 App 变。
    /// 需要跨启动一致的取色/取种子一律走这里。
    var bubuStableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV offset basis
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3          // FNV prime
        }
        return hash
    }

    /// 由稳定哈希得到 0–360 色相，配合 BubuTheme.Color.hue 使用。
    var bubuStableHue: Double { Double(bubuStableHash % 360) }
}

extension UUID {
    /// 由 UUID 得到跨启动稳定的 0–360 色相。
    var bubuStableHue: Double { uuidString.bubuStableHue }

    /// 由 UUID 得到跨启动稳定的非负整型种子（用于 Ken Burns 等确定性动效方向）。
    /// 掩到 63 位保证 >= 0，下游做 abs()/取模不会命中 Int.min 陷阱。
    var bubuStableSeed: Int { Int(uuidString.bubuStableHash & 0x7FFF_FFFF_FFFF_FFFF) }
}

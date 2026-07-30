import Foundation

// MARK: - 回忆照片包（一次 transferFile 送 N 张）
/// 手表要显示照片，就得把照片真的传过去——`applicationContext` 有几十 KB 的硬上限，
/// 塞不进任何有意义的图，所以照片必须走 `transferFile`。
///
/// 为什么打成一个包而不是一张一个文件：`transferFile` 每次调用都是一次独立排队传输，
/// 20 张就是 20 次握手，慢且容易在手表进出可达状态时零碎失败（传到一半的半套照片
/// 会让时光机出现一格有图一格没图）。打成一个包 = 一次传输、要么全到要么全不到。
///
/// 为什么不用 JSON + base64：base64 会把体积撑大 33%（400KB → 530KB），
/// 而这条链路的成本几乎全在字节数上。这里用最朴素的长度前缀二进制容器，零依赖、可单测。
///
/// 容器格式（全部小端）：
/// ```
/// "BPB1"            4 字节魔数
/// count             UInt32  条目数
/// 每条目：
///   nameLength      UInt16  文件名 UTF8 字节数
///   name            nameLength 字节
///   dataLength      UInt32  图片字节数
///   data            dataLength 字节
/// ```
public nonisolated enum WatchPhotoBundle {

    private static let magic: [UInt8] = Array("BPB1".utf8)

    /// 单包大小上限。超了就截断（丢尾部条目），宁可少几张也不要把 WatchConnectivity 撑爆。
    public static let maxBundleBytes = 2 * 1024 * 1024

    // MARK: 编码

    public static func encode(_ items: [(name: String, data: Data)]) -> Data {
        var out = Data(magic)
        var kept: [(name: String, data: Data)] = []
        var total = magic.count + 4
        for item in items {
            let nameBytes = Array(item.name.utf8)
            guard nameBytes.count <= Int(UInt16.max) else { continue }
            let size = 2 + nameBytes.count + 4 + item.data.count
            guard total + size <= maxBundleBytes else { break }
            total += size
            kept.append(item)
        }
        appendUInt32(UInt32(kept.count), to: &out)
        for item in kept {
            let nameBytes = Array(item.name.utf8)
            appendUInt16(UInt16(nameBytes.count), to: &out)
            out.append(contentsOf: nameBytes)
            appendUInt32(UInt32(item.data.count), to: &out)
            out.append(item.data)
        }
        return out
    }

    // MARK: 解码

    /// 解不出来就返回 nil（包被截断/损坏），调用方保留旧缓存而不是清空——
    /// 半套照片比一套旧照片更难看。
    public static func decode(_ data: Data) -> [(name: String, data: Data)]? {
        var cursor = 0
        guard data.count >= magic.count + 4 else { return nil }
        guard Array(data[0..<magic.count]) == magic else { return nil }
        cursor = magic.count
        guard let count = readUInt32(data, &cursor) else { return nil }
        // 条目数当上界用，防被构造的巨大 count 拖进长循环。
        guard count <= 512 else { return nil }

        var result: [(name: String, data: Data)] = []
        for _ in 0..<count {
            guard let nameLen = readUInt16(data, &cursor) else { return nil }
            guard cursor + Int(nameLen) <= data.count else { return nil }
            let nameData = data.subdata(in: cursor..<(cursor + Int(nameLen)))
            guard let name = String(data: nameData, encoding: .utf8) else { return nil }
            cursor += Int(nameLen)
            guard let dataLen = readUInt32(data, &cursor) else { return nil }
            guard cursor + Int(dataLen) <= data.count else { return nil }
            let payload = data.subdata(in: cursor..<(cursor + Int(dataLen)))
            cursor += Int(dataLen)
            result.append((name: name, data: payload))
        }
        return result
    }

    /// 文件名集合的指纹。手机侧据此判断「照片集合有没有变」，没变就不重传，
    /// 省掉每次进前台都推 400KB。
    public static func fingerprint(_ names: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a 64
        for byte in names.sorted().joined(separator: "\u{1}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: 字节工具

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xff))
        }
    }

    private static func readUInt16(_ data: Data, _ cursor: inout Int) -> UInt16? {
        guard cursor + 2 <= data.count else { return nil }
        let lo = UInt16(data[data.startIndex + cursor])
        let hi = UInt16(data[data.startIndex + cursor + 1])
        cursor += 2
        return lo | (hi << 8)
    }

    private static func readUInt32(_ data: Data, _ cursor: inout Int) -> UInt32? {
        guard cursor + 4 <= data.count else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[data.startIndex + cursor + i]) << UInt32(i * 8)
        }
        cursor += 4
        return value
    }
}

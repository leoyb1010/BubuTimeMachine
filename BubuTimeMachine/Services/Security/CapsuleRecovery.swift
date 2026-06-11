import Foundation

// MARK: - 时间胶囊恢复码（v3 真 E2E）
/// 24 词助记词作为家庭时间胶囊的主密钥来源。
/// - 存 iCloud Keychain（家庭同一 Apple ID 设备自动同步）；
/// - 引导用户打印/抄写收进实体盒子（30 年后即使 iCloud 没了，纸条还在）。
/// 词表为 BIP39 风格的常见英文词子集（256 词，零依赖内置）。
enum CapsuleRecovery {
    private static let keychainKey = "bubu.capsule.recoveryCode.v3"

    /// 取当前家庭恢复码；没有则生成一个并存入 iCloud Keychain。
    static func currentOrCreate() -> String {
        if let existing = KeychainStore.icloudString(for: keychainKey), !existing.isEmpty {
            return existing
        }
        let code = generate(wordCount: 24)
        KeychainStore.setICloud(code, for: keychainKey)
        return code
    }

    /// 只读当前恢复码（用于「查看/打印」）。可能为 nil（从未生成）。
    static func current() -> String? {
        KeychainStore.icloudString(for: keychainKey)
    }

    /// 用户手动用纸条恢复码覆盖（换新机、iCloud 丢失场景）。
    static func restore(_ code: String) {
        let normalized = code.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
        KeychainStore.setICloud(normalized, for: keychainKey)
    }

    /// 生成 N 词助记词。用 SystemRandomNumberGenerator（密码学安全）。
    static func generate(wordCount: Int = 24) -> String {
        var rng = SystemRandomNumberGenerator()
        let words = (0..<wordCount).map { _ in wordList[Int.random(in: 0..<wordList.count, using: &rng)] }
        return words.joined(separator: " ")
    }

    /// 256 词常见英文词表（足够 24 词 ≈ 192 bit 熵）。
    static let wordList: [String] = [
        "apple","baby","bear","bird","blue","boat","book","brave","bread","bright",
        "brook","calm","candle","cat","cloud","clover","coral","cozy","cream","daisy",
        "dawn","deer","dream","drift","dusk","earth","ember","fawn","fern","field",
        "fire","fox","frost","garden","gentle","glow","grace","green","happy","harbor",
        "hazel","heart","hill","home","honey","hope","ivory","jade","joy","kind",
        "lake","lamb","leaf","light","lily","linen","lotus","lucky","lunar","maple",
        "meadow","mellow","merry","mild","mint","mist","moon","moss","mother","nest",
        "night","noble","ocean","olive","opal","orange","pansy","peace","peach","pearl",
        "pebble","petal","pine","plum","pond","poppy","quiet","rain","raven","reed",
        "river","robin","rose","ruby","sage","sand","sea","seed","shade","shell",
        "shore","silk","sky","snow","soft","song","spark","spring","star","stone",
        "stork","storm","stream","summer","sun","sunny","swan","sweet","teal","thyme",
        "tide","tiger","topaz","tulip","valley","velvet","violet","warm","water","wave",
        "wheat","willow","wind","winter","wish","wolf","wood","wren","amber","autumn",
        "basil","beach","bell","berry","birch","bloom","blossom","breeze","button","cedar",
        "cherry","chime","cliff","cocoa","comet","cotton","crane","crystal","dahlia","dale",
        "dove","ebony","echo","elm","fable","fairy","feather","fennel","fig","flame",
        "fleece","flora","flutter","forest","fountain","fresh","frond","gale","glade","glimmer",
        "gold","grove","hatch","haven","heath","heron","hollow","ivy","jasmine","jewel",
        "kettle","lagoon","lantern","lark","laurel","lavender","ledge","lemon","lotus","lullaby",
        "marble","marsh","mauve","melody","mesa","mossy","myrtle","nectar","nimbus","oak",
        "oasis","orchid","otter","palm","pasture","pebbly","pepper","plume","pollen","prairie",
        "quartz","quill","ranch","rapids","ridge","ripple","rosemary","rustic","saffron","sapling",
        "scout","sequoia","shimmer","silver","sleet","sparrow","spruce","starling","sugar","sunbeam",
        "sunset","swallow","sycamore","tangerine","thistle","thunder","timber","trail","tranquil","trout",
        "twilight","umber","vale","vapor","vine","walnut","waterfall","whisper","wildflower","windmill",
    ]
}

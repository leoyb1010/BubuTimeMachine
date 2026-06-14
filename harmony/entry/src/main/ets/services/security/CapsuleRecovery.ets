import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { KeychainStore } from './KeychainStore';
import { CapsuleCrypto } from './CapsuleCrypto';

// MARK: - CapsuleRecovery（对照 iOS Services/Security/CapsuleRecovery.swift）
// 24 词助记词作为家庭时间胶囊（v3 真 E2E）的主密钥来源。
// iOS：存 iCloud Keychain（家庭同一 Apple ID 设备自动同步）+ 引导打印纸条。
// HarmonyOS：存 KeychainStore 的 icloud 命名空间（持久化等价），同样引导打印纸条。
// 词表为 BIP39 风格的常见英文词子集（零依赖内置），随机源用密码学安全的 cryptoFramework random。
export class CapsuleRecovery {
  private static readonly keychainKey: string = 'bubu.capsule.recoveryCode.v3';

  // 取当前家庭恢复码；没有则生成一个并存入 Keychain。
  static currentOrCreate(): string {
    const existing = KeychainStore.icloudString(CapsuleRecovery.keychainKey);
    if (existing && existing.length > 0) return existing;
    const code = CapsuleRecovery.generate(24);
    KeychainStore.setICloud(code, CapsuleRecovery.keychainKey);
    return code;
  }

  // 只读当前恢复码（用于「查看/打印」）。可能为 null（从未生成）。
  static current(): string | null {
    return KeychainStore.icloudString(CapsuleRecovery.keychainKey);
  }

  // 用户手动用纸条恢复码覆盖（换新机、丢失场景）。
  static restore(code: string): void {
    const normalized = CapsuleCrypto.normalizeRecoveryCode(code);
    KeychainStore.setICloud(normalized, CapsuleRecovery.keychainKey);
  }

  // 生成 N 词助记词。用密码学安全的随机数（对照 SystemRandomNumberGenerator）。
  static generate(wordCount: number = 24): string {
    const words: string[] = [];
    for (let i = 0; i < wordCount; i++) {
      const idx = CapsuleRecovery.secureRandomIndex(CapsuleRecovery.wordList.length);
      words.push(CapsuleRecovery.wordList[idx]);
    }
    return words.join(' ');
  }

  // 无偏的密码学安全索引（拒绝采样，避免取模偏差）。
  private static secureRandomIndex(bound: number): number {
    const rand = cryptoFramework.createRandom();
    const limit = Math.floor(0x100000000 / bound) * bound; // 2^32 对 bound 取整
    while (true) {
      const bytes = rand.generateRandomSync(4).data;
      const value = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
      if (value < limit) return value % bound;
    }
  }

  // 256 词常见英文词表（足够 24 词 ≈ 192 bit 熵）。
  static readonly wordList: string[] = [
    'apple', 'baby', 'bear', 'bird', 'blue', 'boat', 'book', 'brave', 'bread', 'bright',
    'brook', 'calm', 'candle', 'cat', 'cloud', 'clover', 'coral', 'cozy', 'cream', 'daisy',
    'dawn', 'deer', 'dream', 'drift', 'dusk', 'earth', 'ember', 'fawn', 'fern', 'field',
    'fire', 'fox', 'frost', 'garden', 'gentle', 'glow', 'grace', 'green', 'happy', 'harbor',
    'hazel', 'heart', 'hill', 'home', 'honey', 'hope', 'ivory', 'jade', 'joy', 'kind',
    'lake', 'lamb', 'leaf', 'light', 'lily', 'linen', 'lotus', 'lucky', 'lunar', 'maple',
    'meadow', 'mellow', 'merry', 'mild', 'mint', 'mist', 'moon', 'moss', 'mother', 'nest',
    'night', 'noble', 'ocean', 'olive', 'opal', 'orange', 'pansy', 'peace', 'peach', 'pearl',
    'pebble', 'petal', 'pine', 'plum', 'pond', 'poppy', 'quiet', 'rain', 'raven', 'reed',
    'river', 'robin', 'rose', 'ruby', 'sage', 'sand', 'sea', 'seed', 'shade', 'shell',
    'shore', 'silk', 'sky', 'snow', 'soft', 'song', 'spark', 'spring', 'star', 'stone',
    'stork', 'storm', 'stream', 'summer', 'sun', 'sunny', 'swan', 'sweet', 'teal', 'thyme',
    'tide', 'tiger', 'topaz', 'tulip', 'valley', 'velvet', 'violet', 'warm', 'water', 'wave',
    'wheat', 'willow', 'wind', 'winter', 'wish', 'wolf', 'wood', 'wren', 'amber', 'autumn',
    'basil', 'beach', 'bell', 'berry', 'birch', 'bloom', 'blossom', 'breeze', 'button', 'cedar',
    'cherry', 'chime', 'cliff', 'cocoa', 'comet', 'cotton', 'crane', 'crystal', 'dahlia', 'dale',
    'dove', 'ebony', 'echo', 'elm', 'fable', 'fairy', 'feather', 'fennel', 'fig', 'flame',
    'fleece', 'flora', 'flutter', 'forest', 'fountain', 'fresh', 'frond', 'gale', 'glade', 'glimmer',
    'gold', 'grove', 'hatch', 'haven', 'heath', 'heron', 'hollow', 'ivy', 'jasmine', 'jewel',
    'kettle', 'lagoon', 'lantern', 'lark', 'laurel', 'lavender', 'ledge', 'lemon', 'lotus', 'lullaby',
    'marble', 'marsh', 'mauve', 'melody', 'mesa', 'mossy', 'myrtle', 'nectar', 'nimbus', 'oak',
    'oasis', 'orchid', 'otter', 'palm', 'pasture', 'pebbly', 'pepper', 'plume', 'pollen', 'prairie',
    'quartz', 'quill', 'ranch', 'rapids', 'ridge', 'ripple', 'rosemary', 'rustic', 'saffron', 'sapling',
    'scout', 'sequoia', 'shimmer', 'silver', 'sleet', 'sparrow', 'spruce', 'starling', 'sugar', 'sunbeam',
    'sunset', 'swallow', 'sycamore', 'tangerine', 'thistle', 'thunder', 'timber', 'trail', 'tranquil', 'trout',
    'twilight', 'umber', 'vale', 'vapor', 'vine', 'walnut', 'waterfall', 'whisper', 'wildflower', 'windmill'
  ];
}

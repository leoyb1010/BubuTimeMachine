import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util, buffer } from '@kit.ArkTS';

// MARK: - CapsuleCrypto（对照 iOS Services/Security/CapsuleCrypto.swift）
// AES-GCM 加密。密钥派生绑定解锁时间——到期前 UI 不可解。
// iOS 用 CryptoKit（SHA256 派生 SymmetricKey + AES.GCM.seal/open）；
// 这里用 @kit.CryptoArchitectureKit cryptoFramework：
//   - SHA256          ←→ cryptoFramework.createMd('SHA256')
//   - AES256-GCM      ←→ createCipher('AES256|GCM|NoPadding') + GcmParamsSpec
//   - SymmetricKey    ←→ 32 字节密钥经 SymKeyGenerator.convertKey 还原
// combined blob 布局与 CryptoKit 对齐：nonce(12) + ciphertext + tag(16)，
// 便于跨端互解（v2/v3 带魔数前缀；v1 历史无前缀）。
//
// v2（当前）：密钥由「规范化 ISO8601 字符串(整秒, UTC) + salt」派生。
// v1（历史）：密钥由 timeIntervalSince1970（含亚秒小数）派生；仅用于解旧 blob。
// v3（真 E2E）：密钥由「24 词助记词 + salt」派生，密钥不随记录同步。

// 解锁未到期 / 解密失败的错误类型（对照 CryptoError）。
export class CapsuleCryptoError extends Error {
  readonly kind: 'stillLocked' | 'decryptionFailed';
  readonly unlockAt?: number; // 毫秒时间戳（stillLocked 时携带）

  constructor(kind: 'stillLocked' | 'decryptionFailed', message: string, unlockAt?: number) {
    super(message);
    this.kind = kind;
    this.unlockAt = unlockAt;
    this.name = 'CapsuleCryptoError';
  }

  static stillLocked(unlockAtMs: number): CapsuleCryptoError {
    return new CapsuleCryptoError('stillLocked', '这封信还没到可以打开的时间哦', unlockAtMs);
  }

  static decryptionFailed(): CapsuleCryptoError {
    return new CapsuleCryptoError('decryptionFailed', '信件打不开了，请检查备份');
  }
}

const GCM_NONCE_LEN = 12;
const GCM_TAG_LEN = 16;

export class CapsuleCrypto {
  static readonly shared = new CapsuleCrypto();

  private constructor() {}

  // v2 / v3 魔数前缀（"BTC2" / "BTC3" 的 UTF-8 字节）。
  private static readonly v2Magic: Uint8Array = new Uint8Array([0x42, 0x54, 0x43, 0x32]);
  private static readonly v3Magic: Uint8Array = new Uint8Array([0x42, 0x54, 0x43, 0x33]);

  // 把解锁时间（毫秒）规整到整秒——封存与派生都必须用规整后的值。
  static normalizedMs(dateMs: number): number {
    return Math.floor(dateMs / 1000) * 1000;
  }

  // 规范化字符串：整秒 UTC ISO8601，跨设备/跨序列化稳定。
  // 对照 iOS ISO8601DateFormatter（UTC、整秒，形如 2026-06-14T00:00:00Z）。
  private static canonicalString(dateMs: number): string {
    const sec = CapsuleCrypto.normalizedMs(dateMs);
    return new Date(sec).toISOString().replace(/\.\d{3}Z$/, 'Z');
  }

  // MARK: - 派生工具
  private static async sha256(material: string): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256');
    const data: cryptoFramework.DataBlob = { data: new Uint8Array(buffer.from(material, 'utf-8').buffer) };
    await md.update(data);
    const digest = await md.digest();
    return digest.data;
  }

  // v2：规范化时间字符串 + salt 派生。
  private static async deriveKeyV2(unlockAtMs: number, salt: string): Promise<Uint8Array> {
    const material = `${CapsuleCrypto.canonicalString(unlockAtMs)}|${salt}|bubu-time-capsule-v2`;
    return CapsuleCrypto.sha256(material);
  }

  // v1 历史派生（仅用于解开旧 blob）。unlockInterval 为秒（可含小数）。
  private static async deriveKeyV1(unlockIntervalSec: number, salt: string): Promise<Uint8Array> {
    const material = `${unlockIntervalSec}|${salt}|bubu-time-capsule`;
    return CapsuleCrypto.sha256(material);
  }

  // v3：助记词归一化（小写、压缩空白）+ salt 派生。
  async deriveKeyV3(recoveryCode: string, salt: string): Promise<Uint8Array> {
    const normalized = CapsuleCrypto.normalizeRecoveryCode(recoveryCode);
    const material = `${normalized}|${salt}|bubu-time-capsule-v3`;
    return CapsuleCrypto.sha256(material);
  }

  // 归一化助记词：小写、按空白拆分后单空格连接（对照 iOS split/joined）。
  static normalizeRecoveryCode(code: string): string {
    return code
      .toLowerCase()
      .split(/[\s]+/)
      .filter((w: string): boolean => w.length > 0)
      .join(' ');
  }

  // MARK: - AES-GCM 原语
  private static async makeSymKey(keyBytes: Uint8Array): Promise<cryptoFramework.SymKey> {
    const gen = cryptoFramework.createSymKeyGenerator('AES256');
    const blob: cryptoFramework.DataBlob = { data: keyBytes };
    return gen.convertKey(blob);
  }

  // 加密：随机 12 字节 nonce，输出 combined = nonce + ciphertext + tag。
  private static async sealGcm(plaintext: Uint8Array, keyBytes: Uint8Array): Promise<Uint8Array> {
    const key = await CapsuleCrypto.makeSymKey(keyBytes);
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const nonce = new Uint8Array(GCM_NONCE_LEN);
    cryptoFramework.createRandom().generateRandomSync(GCM_NONCE_LEN).data.forEach((b: number, i: number) => {
      nonce[i] = b;
    });
    const tagBlob: cryptoFramework.DataBlob = { data: new Uint8Array(GCM_TAG_LEN) };
    const spec: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: new Uint8Array(0) },
      authTag: tagBlob
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, spec);
    const ctBlob = await cipher.doFinal({ data: plaintext });
    // doFinal 在 GCM 加密时返回 ciphertext+tag；规整为 nonce + ciphertext + tag。
    const body = ctBlob.data;
    const combined = new Uint8Array(GCM_NONCE_LEN + body.length);
    combined.set(nonce, 0);
    combined.set(body, GCM_NONCE_LEN);
    return combined;
  }

  // 解密 combined = nonce + ciphertext + tag。失败抛 decryptionFailed。
  private static async openGcm(combined: Uint8Array, keyBytes: Uint8Array): Promise<Uint8Array> {
    if (combined.length < GCM_NONCE_LEN + GCM_TAG_LEN) {
      throw CapsuleCryptoError.decryptionFailed();
    }
    try {
      const nonce = combined.slice(0, GCM_NONCE_LEN);
      const ctAndTag = combined.slice(GCM_NONCE_LEN);
      const ctLen = ctAndTag.length - GCM_TAG_LEN;
      const ciphertext = ctAndTag.slice(0, ctLen);
      const tag = ctAndTag.slice(ctLen);
      const key = await CapsuleCrypto.makeSymKey(keyBytes);
      const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const spec: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: tag }
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, spec);
      const out = await cipher.doFinal({ data: ciphertext });
      return out.data;
    } catch (e) {
      throw CapsuleCryptoError.decryptionFailed();
    }
  }

  // MARK: - 前缀工具
  private static hasPrefix(data: Uint8Array, prefix: Uint8Array): boolean {
    if (data.length < prefix.length) return false;
    for (let i = 0; i < prefix.length; i++) {
      if (data[i] !== prefix[i]) return false;
    }
    return true;
  }

  private static withMagic(magic: Uint8Array, body: Uint8Array): Uint8Array {
    const out = new Uint8Array(magic.length + body.length);
    out.set(magic, 0);
    out.set(body, magic.length);
    return out;
  }

  static isV3(ciphertext: Uint8Array): boolean {
    return CapsuleCrypto.hasPrefix(ciphertext, CapsuleCrypto.v3Magic);
  }

  // MARK: - v2 加解密
  async encrypt(plaintext: Uint8Array, unlockAtMs: number, salt: string): Promise<Uint8Array> {
    const key = await CapsuleCrypto.deriveKeyV2(unlockAtMs, salt);
    const combined = await CapsuleCrypto.sealGcm(plaintext, key);
    return CapsuleCrypto.withMagic(CapsuleCrypto.v2Magic, combined);
  }

  // 解密。到期前拒绝（UI 层也会拦截，这里是第二道防线）。
  async decrypt(ciphertext: Uint8Array, unlockAtMs: number, salt: string, nowMs: number = Date.now()): Promise<Uint8Array> {
    if (nowMs < CapsuleCrypto.normalizedMs(unlockAtMs)) {
      throw CapsuleCryptoError.stillLocked(unlockAtMs);
    }
    if (CapsuleCrypto.hasPrefix(ciphertext, CapsuleCrypto.v2Magic)) {
      const body = ciphertext.slice(CapsuleCrypto.v2Magic.length);
      const key = await CapsuleCrypto.deriveKeyV2(unlockAtMs, salt);
      return CapsuleCrypto.openGcm(body, key);
    }
    // v1 旧 blob：先按当前值原样尝试，再尝试整秒取整（同步截断前后两种可能）。
    const intervalSec = unlockAtMs / 1000;
    const floored = Math.floor(intervalSec);
    const candidates: number[] = [intervalSec];
    if (intervalSec !== floored) candidates.push(floored);
    for (const candidate of candidates) {
      try {
        const key = await CapsuleCrypto.deriveKeyV1(candidate, salt);
        return await CapsuleCrypto.openGcm(ciphertext, key);
      } catch (e) {
        // 试下一个候选
      }
    }
    throw CapsuleCryptoError.decryptionFailed();
  }

  // MARK: - v3 真 E2E 加解密
  async encryptV3(plaintext: Uint8Array, recoveryCode: string, salt: string): Promise<Uint8Array> {
    const key = await this.deriveKeyV3(recoveryCode, salt);
    const combined = await CapsuleCrypto.sealGcm(plaintext, key);
    return CapsuleCrypto.withMagic(CapsuleCrypto.v3Magic, combined);
  }

  async decryptV3(ciphertext: Uint8Array, recoveryCode: string, salt: string,
                  unlockAtMs: number, nowMs: number = Date.now()): Promise<Uint8Array> {
    if (nowMs < CapsuleCrypto.normalizedMs(unlockAtMs)) {
      throw CapsuleCryptoError.stillLocked(unlockAtMs);
    }
    if (!CapsuleCrypto.hasPrefix(ciphertext, CapsuleCrypto.v3Magic)) {
      throw CapsuleCryptoError.decryptionFailed();
    }
    const body = ciphertext.slice(CapsuleCrypto.v3Magic.length);
    const key = await this.deriveKeyV3(recoveryCode, salt);
    return CapsuleCrypto.openGcm(body, key);
  }

  // 文本 <-> 字节（供 Vault 序列化 JSON 载荷使用）。
  static utf8Encode(text: string): Uint8Array {
    return new Uint8Array(buffer.from(text, 'utf-8').buffer);
  }

  static utf8Decode(bytes: Uint8Array): string {
    return buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('utf-8');
  }
}

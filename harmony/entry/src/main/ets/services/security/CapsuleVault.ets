import { fileIo } from '@kit.CoreFileKit';
import { util, buffer } from '@kit.ArkTS';
import { CapsuleCrypto, CapsuleCryptoError } from './CapsuleCrypto';
import { MediaStore } from '../MediaStore';

// MARK: - CapsuleVault（对照 iOS Services/Security/CapsuleVault.swift）
// 负责把 CapsulePayload 加密写入沙盒、到期解密读出。
// 密钥由 CapsuleCrypto 依据 unlockAt（v2）或恢复码（v3）派生——篡改解锁时间则无法解出。
//
// iOS 的 MediaStore 有 saveBlob / blob(named:) / data(forMedia:) / fileExists；
// HarmonyOS 端的 MediaStore 暂无这些方法，故这里用 @kit.CoreFileKit fileIo 在
// MediaStore 管理的 Media 目录下自包含读写加密 blob（与 MediaStore.fullPath 同根）。

// MARK: - 时间胶囊载荷（对照 iOS CapsulePayload）
// 一封时间胶囊的全部内容，序列化后整体 AES-GCM 加密落盘。
// embeddedVoiceData 以 base64 字符串承载（JSON 友好；对照 iOS 的 Data 自动 base64 编码）。
export interface CapsulePayload {
  letter: string;                       // 写给未来布布的信
  voiceFileName?: string;               // 语音文件名（已加密的 .m4a blob）
  voiceDuration: number;
  voiceWaveform: number[];
  photoFileNames: string[];             // 附带照片（已加密的 blob）
  embeddedVoiceData?: string;           // base64 编码的语音原文件字节
  embeddedVoiceFileExtension?: string;
}

export function makeCapsulePayload(letter: string = ''): CapsulePayload {
  return {
    letter,
    voiceDuration: 0,
    voiceWaveform: [],
    photoFileNames: []
  };
}

export class CapsuleVault {
  static readonly shared = new CapsuleVault();

  private crypto: CapsuleCrypto = CapsuleCrypto.shared;
  private mediaStore: MediaStore = MediaStore.shared;

  private constructor() {}

  // MARK: - blob 文件 I/O（自包含，落到 MediaStore 的 Media 目录）
  private blobPath(fileName: string): string {
    return this.mediaStore.fullPath(fileName);
  }

  // 把加密 blob 写盘，返回随机文件名。
  private saveBlob(data: Uint8Array, preferredExtension: string = 'btc'): string {
    const name = `${util.generateRandomUUID(true)}.${preferredExtension}`;
    const path = this.blobPath(name);
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.writeSync(file.fd, data.buffer);
    } finally {
      fileIo.closeSync(file);
    }
    return name;
  }

  // 读出 blob 字节；不存在/失败返回 null。
  private readBlob(fileName: string): Uint8Array | null {
    const path = this.blobPath(fileName);
    try {
      if (!fileIo.accessSync(path)) return null;
      const stat = fileIo.statSync(path);
      const arr = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const read = fileIo.readSync(file.fd, arr);
        return new Uint8Array(arr.slice(0, read));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      return null;
    }
  }

  // 读取一个已加密媒体文件的原始字节（对照 mediaStore.data(forMedia:)）。
  private mediaData(fileName: string): Uint8Array | null {
    return this.readBlob(fileName);
  }

  // MARK: - 封存（v2：密钥绑定解锁时间）
  // 加密并落盘，返回加密 blob 文件名。salt 用胶囊 id 保证每封信密钥唯一。
  async seal(payload: CapsulePayload, unlockAtMs: number, salt: string): Promise<string> {
    const prepared = this.embedVoiceIfNeeded(payload);
    const plain = CapsuleCrypto.utf8Encode(JSON.stringify(prepared));
    const cipher = await this.crypto.encrypt(plain, unlockAtMs, salt);
    return this.saveBlob(cipher);
  }

  // v3 真 E2E 封存：密钥来自家庭恢复码，不随记录同步。
  async sealV3(payload: CapsulePayload, recoveryCode: string, salt: string): Promise<string> {
    const prepared = this.embedVoiceIfNeeded(payload);
    const plain = CapsuleCrypto.utf8Encode(JSON.stringify(prepared));
    const cipher = await this.crypto.encryptV3(plain, recoveryCode, salt);
    return this.saveBlob(cipher);
  }

  // 把语音原文件字节内嵌进载荷（对照 iOS：若有 voiceFileName 且未内嵌则读盘内嵌）。
  private embedVoiceIfNeeded(payload: CapsulePayload): CapsulePayload {
    const out: CapsulePayload = {
      letter: payload.letter,
      voiceFileName: payload.voiceFileName,
      voiceDuration: payload.voiceDuration,
      voiceWaveform: payload.voiceWaveform,
      photoFileNames: payload.photoFileNames,
      embeddedVoiceData: payload.embeddedVoiceData,
      embeddedVoiceFileExtension: payload.embeddedVoiceFileExtension
    };
    const voiceName = out.voiceFileName;
    if (voiceName && voiceName.length > 0 && !out.embeddedVoiceData) {
      const data = this.mediaData(voiceName);
      if (data) {
        out.embeddedVoiceData = buffer.from(data.buffer).toString('base64');
        const ext = CapsuleVault.pathExtension(voiceName);
        out.embeddedVoiceFileExtension = ext.length === 0 ? 'm4a' : ext;
      }
    }
    return out;
  }

  // MARK: - 解封（到期解密读出）
  // 未到期抛 CapsuleCryptoError.stillLocked。
  // v3 blob 需提供 recoveryCode；v1/v2 自动按旧逻辑解。
  async unseal(fileName: string, unlockAtMs: number, salt: string,
               recoveryCode?: string, nowMs: number = Date.now()): Promise<CapsulePayload> {
    const cipher = this.readBlob(fileName);
    if (!cipher) {
      throw CapsuleCryptoError.decryptionFailed();
    }
    let plainBytes: Uint8Array;
    if (CapsuleCrypto.isV3(cipher)) {
      if (!recoveryCode || recoveryCode.length === 0) {
        throw CapsuleCryptoError.decryptionFailed();
      }
      plainBytes = await this.crypto.decryptV3(cipher, recoveryCode, salt, unlockAtMs, nowMs);
    } else {
      plainBytes = await this.crypto.decrypt(cipher, unlockAtMs, salt, nowMs);
    }
    const payload = JSON.parse(CapsuleCrypto.utf8Decode(plainBytes)) as CapsulePayload;
    // 若内嵌了语音字节且本地没有对应文件，则落盘还原成可播放文件。
    const embedded = payload.embeddedVoiceData;
    if (embedded && embedded.length > 0) {
      const existingName = payload.voiceFileName;
      const hasExistingFile = existingName !== undefined && existingName.length > 0
        ? this.mediaStore.exists(existingName)
        : false;
      if (!hasExistingFile) {
        const ext = payload.embeddedVoiceFileExtension ?? 'm4a';
        const bytes = new Uint8Array(buffer.from(embedded, 'base64').buffer);
        payload.voiceFileName = this.saveBlob(bytes, ext);
      }
    }
    return payload;
  }

  // 取文件名扩展名（不含点）；无则空串。
  private static pathExtension(fileName: string): string {
    const dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot === fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }
}

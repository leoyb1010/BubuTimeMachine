import { UploadedFileResult } from './DTOs';

// MARK: - Mock API 客户端（对照 iOS Services/Networking/MockAPIClient.swift）
// M0/M1 阶段使用：无需真实 PocketBase，本地闭环即可跑通完整体验。
// 所有方法返回合理的假数据，模拟网络延迟与上传进度。
// 公开面与 APIClient 对齐（同名方法 + shared 单例），可作离线替身。
export class MockAPIClient {
  static readonly shared = new MockAPIClient();

  private constructor() {}

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms));
  }

  // 鉴权：直接返回成功。
  async authenticate(): Promise<boolean> {
    await this.sleep(200);
    return true;
  }

  // upsert：回填一个 mock id，本地优先不打服务器。
  async upsert(collection: string, localId: string, body: Record<string, Object>): Promise<Record<string, Object>> {
    await this.sleep(200);
    const result: Record<string, Object> = {};
    const keys = Object.keys(body);
    for (const k of keys) result[k] = body[k];
    result['id'] = `mock-${localId}`;
    result['localId'] = localId;
    return result;
  }

  // 拉取：本地优先，M1 阶段时光轴只读本地数据，返回空。
  async fetchRecords(collection: string, sinceISO?: string): Promise<Record<string, Object>[]> {
    await this.sleep(200);
    return [];
  }

  // 删除：mock 不做事。
  async deleteRecord(collection: string, id: string): Promise<void> {
    await this.sleep(100);
  }

  // 按 localId 查：mock 总是查不到（走 POST 创建路径）。
  async findByLocalId(collection: string, localId: string): Promise<Record<string, Object> | null> {
    return null;
  }

  // 文件直链：返回 mock 地址。
  fileURL(collection: string, recordId: string, fileName: string): string {
    if (recordId.length === 0 || fileName.length === 0) return '';
    return `https://mock.local/files/${collection}/${recordId}/${fileName}`;
  }

  // 上传：模拟分片进度后返回 mock 结果。
  async uploadFile(
    collection: string,
    localId: string,
    fields: Record<string, string>,
    fileField: string,
    filePath: string,
    fileName: string,
    onProgress?: (fraction: number) => void
  ): Promise<UploadedFileResult> {
    for (let step = 1; step <= 10; step++) {
      await this.sleep(120);
      if (onProgress) onProgress(step / 10.0);
    }
    return { recordId: `mock-file-${localId}`, storedFileName: fileName };
  }

  // 下载：mock 不实际落盘，直接返回目标路径。
  async downloadFile(remoteURL: string, destPath: string): Promise<string> {
    await this.sleep(150);
    return destPath;
  }

  // 连接测试：总是通。
  async ping(): Promise<boolean> {
    await this.sleep(150);
    return true;
  }
}

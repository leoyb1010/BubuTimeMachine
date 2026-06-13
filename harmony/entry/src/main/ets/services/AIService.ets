import { http } from '@kit.NetworkKit';
import { ServerConfig } from './ServerConfig';

// MARK: - AI 服务（对照 iOS BubuAIService）
// 对接自托管 FastAPI：一句话自然语言 → 结构化建议。只发文字，不上传照片。
export interface NaturalCaptureResult {
  note: string;       // 规整后的记录文字
  mood?: string;      // 识别到的心情
  domain?: string;    // 归类：日常/健康/里程碑…
}

export class AIService {
  static readonly shared = new AIService();
  private constructor() {}

  private get baseURL(): string {
    // iOS 用单独的 AI 地址；这里复用服务器地址 + /ai 前缀，可在设置里改。
    return ServerConfig.shared.baseURLString.replace(/\/+$/, '');
  }

  get isConfigured(): boolean {
    return this.baseURL.length > 0;
  }

  // 一句话解析。失败抛错，UI 层降级为「直接存原文」。
  async parseNaturalCapture(text: string): Promise<NaturalCaptureResult> {
    const req = http.createHttp();
    try {
      const body = JSON.stringify({ text: text, child_name: ServerConfig.shared.childName });
      const resp = await req.request(this.baseURL + '/parse-natural-capture', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' } as Record<string, string>,
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 90000
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const obj = JSON.parse(resp.result as string) as Record<string, string>;
      const result: NaturalCaptureResult = {
        note: (obj.note as string) ?? text,
        mood: obj.mood as string,
        domain: obj.domain as string
      };
      return result;
    } finally {
      req.destroy();
    }
  }
}

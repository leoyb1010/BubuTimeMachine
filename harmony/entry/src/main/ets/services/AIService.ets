import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ServerConfig } from './ServerConfig';
import { Media } from '../models/Models';
import {
  NaturalCaptureRequest,
  NaturalCaptureParseResult,
  decodeParseResult
} from './NaturalCaptureDTO';

// MARK: - AI 服务（对照 iOS Services/AI/AIService.swift + BubuAIService.swift）
// 隐私至上：AI 能力全部自托管 FastAPI（背后接 DeepSeek），UI 永不依赖具体后端。
// 任意一步失败都抛错，UI 层各视图自行降级（保留 Mock 体验或提示稍后再试）。只发文字，不上传照片。

// AI 对一条 Entry 的归类结果（对照 DTOs.swift AIClassification）。
export interface AIClassification {
  suggestedTitle?: string;
  eventCluster?: string;       // 用于时光轴按"事件"重排
  placeName?: string;
  visualTags: string[];
}

// "这是第一次吗"识别建议（对照 DTOs.swift FirstTimeSuggestion）。
export interface FirstTimeSuggestion {
  what: string;                // "第一次吃西瓜"
  confidence: number;          // 0...1
}

// 年度成长电影生成任务句柄（对照 DTOs.swift GrowthMovieJob）。
export interface GrowthMovieJob {
  jobId: string;
  year: number;
  status: string;              // pending / generating / ready / failed
}

// 简化版自然语言解析结果（保留原有公共接口：HomeView 直接取 note/mood/domain）。
// 与 NaturalCaptureDTO.ets 的结构化 NaturalCaptureParseResult 区分使用。
export interface NaturalCaptureResult {
  note: string;       // 规整后的记录文字
  mood?: string;      // 识别到的心情
  domain?: string;    // 归类：日常/健康/里程碑…
}

// /parse-natural-capture 请求体线格式（snake_case，对照服务端与 iOS .iso8601 编码）。
interface ParseRequestWire {
  text: string;
  child_name: string;
  timezone: string;
  reference_date: string;
}

export class AIService {
  static readonly shared = new AIService();
  private constructor() {}

  private get baseURL(): string {
    return ServerConfig.shared.aiBaseURLString.replace(/\/+$/, '');
  }

  private get apiKey(): string {
    return ServerConfig.shared.aiAPIKey;
  }

  get isConfigured(): boolean {
    return ServerConfig.shared.isAIConfigured;
  }

  // 鉴权头：有 key 时带上 X-API-Key（对照 BubuAIService.applyAuth）。
  private authHeader(): Record<string, string> {
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.apiKey.length > 0) {
      header['X-API-Key'] = this.apiKey;
      // 兼容旧调用方使用 Bearer 鉴权的服务端。
      header['Authorization'] = `Bearer ${this.apiKey}`;
    }
    return header;
  }

  // 连通性探测（对照 ping）。服务端开启鉴权且 key 不对时返回 false。
  async ping(): Promise<boolean> {
    const req = http.createHttp();
    try {
      const resp = await req.request(this.baseURL + '/health', {
        method: http.RequestMethod.GET,
        header: this.authHeader(),
        connectTimeout: 30000,
        readTimeout: 90000
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const obj = JSON.parse(resp.result as string) as Record<string, Object>;
      const auth = obj['auth'] as boolean | undefined;
      if (auth === false && this.apiKey.length > 0) return false;
      return true;
    } finally {
      req.destroy();
    }
  }

  // 第一人称改写（对照 rewriteFirstPerson）。
  async rewriteFirstPerson(note: string, childName: string): Promise<string> {
    const body: Record<string, Object> = { 'note': note, 'child_name': childName };
    const obj = await this.post('rewrite-first-person', body);
    return (obj['first_person'] as string | undefined) ?? '';
  }

  // 富归类：文字 + 标签 + 地点（对照 classifyContent）。
  async classifyContent(note: string | undefined, tags: string[], locationName: string | undefined): Promise<AIClassification> {
    const body: Record<string, Object> = {
      'note': note ?? '',
      'tags': tags,
      'location_name': locationName ?? ''
    };
    const obj = await this.post('classify', body);
    const visual = obj['visual_tags'] as string[] | undefined;
    return {
      suggestedTitle: obj['suggested_title'] as string | undefined,
      eventCluster: obj['event_cluster'] as string | undefined,
      placeName: (obj['place_name'] as string | undefined) ?? locationName,
      visualTags: visual ?? tags
    };
  }

  // "第一次"识别（对照 detectFirstTime）。标签去重后请求；无标签或非首次返回 undefined。
  async detectFirstTime(media: Media[]): Promise<FirstTimeSuggestion | undefined> {
    const set = new Set<string>();
    for (const m of media) {
      for (const t of m.aiTags) set.add(t);
    }
    const tags = Array.from(set);
    if (tags.length === 0) return undefined;
    const body: Record<string, Object> = { 'tags': tags };
    const obj = await this.post('detect-first-time', body);
    const isFirst = obj['is_first'] as boolean | undefined;
    const what = obj['what'] as string | undefined;
    if (isFirst !== true || what === undefined) return undefined;
    return { what: what, confidence: (obj['confidence'] as number | undefined) ?? 0.5 };
  }

  // 语音转写（对照 transcribe）。
  // NOTE: iOS 走 multipart/form-data 上传本地音频文件。HarmonyOS http 的 multipart 需手工拼包，
  // 此处保留 1:1 端点与返回字段语义，传入已可访问的本地文件路径并以表单上传。
  async transcribe(audioFilePath: string): Promise<string> {
    const req = http.createHttp();
    try {
      const fileName = audioFilePath.split('/').pop() ?? 'audio';
      const header: Record<string, string> = {};
      if (this.apiKey.length > 0) {
        header['X-API-Key'] = this.apiKey;
        header['Authorization'] = `Bearer ${this.apiKey}`;
      }
      const resp = await req.request(this.baseURL + '/transcribe', {
        method: http.RequestMethod.POST,
        header: header,
        // multipart 表单：单文件字段 file（对照 iOS form-data name="file"）。
        multiFormDataList: [
          {
            name: 'file',
            contentType: 'application/octet-stream',
            remoteFileName: fileName,
            filePath: audioFilePath
          }
        ],
        connectTimeout: 30000,
        readTimeout: 90000
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const obj = JSON.parse(resp.result as string) as Record<string, Object>;
      return (obj['transcript'] as string | undefined) ?? '';
    } finally {
      req.destroy();
    }
  }

  // 成长电影生成（对照 generateGrowthMovie）。旁白生成；成片在服务端拼接，前端流程占位。
  async generateGrowthMovie(year: number): Promise<GrowthMovieJob> {
    const body: Record<string, Object> = { 'year': year, 'child_name': '布布' };
    const obj = await this.post('movie-narration', body);
    const narration = (obj['narration'] as string | undefined) ?? '';
    return {
      jobId: `ai-${year}`,
      year: year,
      status: narration.length === 0 ? 'failed' : 'ready'
    };
  }

  // 旁白文本（对照 movieNarration，供成长电影视图直接取用）。
  async movieNarration(year: number, childName: string, highlights: string[]): Promise<string> {
    const body: Record<string, Object> = {
      'year': year,
      'child_name': childName,
      'highlights': highlights
    };
    const obj = await this.post('movie-narration', body);
    return (obj['narration'] as string | undefined) ?? '';
  }

  // MARK: - 自然语言解析

  // 一句话解析（保留原公共接口）。失败抛错，UI 层降级为「直接存原文」。
  // 对照 server /parse-natural-capture 的简化取用：note/mood/domain。
  async parseNaturalCapture(text: string): Promise<NaturalCaptureResult> {
    const body: Record<string, Object> = {
      'text': text,
      'child_name': ServerConfig.shared.childName
    };
    const obj = await this.post('parse-natural-capture', body);
    return {
      note: (obj['note'] as string | undefined) ?? text,
      mood: obj['mood'] as string | undefined,
      domain: obj['domain'] as string | undefined
    };
  }

  // 结构化解析（对照 iOS parseNaturalCapture(_:NaturalCaptureRequest)）。
  // 一句话自然语言 → 多条结构化记录（疫苗/成长/餐食/喝水/睡眠/不舒服/时光…）。
  async parseNaturalCaptureFull(request: NaturalCaptureRequest): Promise<NaturalCaptureParseResult> {
    const req = http.createHttp();
    try {
      const body = JSON.stringify({
        text: request.text,
        child_name: request.childName,
        timezone: request.timezone,
        reference_date: request.referenceDate
      } as ParseRequestWire);
      const resp = await req.request(this.baseURL + '/parse-natural-capture', {
        method: http.RequestMethod.POST,
        header: this.authHeader(),
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 90000
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const obj = JSON.parse(resp.result as string) as Record<string, Object>;
      return decodeParseResult(obj);
    } finally {
      req.destroy();
    }
  }

  // MARK: - 私有

  // 通用 JSON POST（对照 BubuAIService.post + check）。非 2xx 抛 APIError.server 等价错误。
  private async post(path: string, body: Record<string, Object>): Promise<Record<string, Object>> {
    const req = http.createHttp();
    try {
      const resp = await req.request(this.baseURL + '/' + path, {
        method: http.RequestMethod.POST,
        header: this.authHeader(),
        extraData: JSON.stringify(body),
        connectTimeout: 30000,
        readTimeout: 90000
      });
      const code = resp.responseCode;
      if (code < 200 || code >= 300) {
        const raw = resp.result as string;
        const msg = raw.length > 200 ? raw.substring(0, 200) : raw;
        throw new Error(`HTTP ${code}: ${msg}`);
      }
      const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
      return parsed;
    } finally {
      req.destroy();
    }
  }
}

// 生成 ISO8601 参考时间（供调用方构造 NaturalCaptureRequest，对照 iOS .iso8601 编码）。
export function nowISO(): string {
  return new Date().toISOString();
}

// 生成一条 UUID（对照 NaturalCaptureItem id: UUID）。
export function newUUID(): string {
  return util.generateRandomUUID(true);
}

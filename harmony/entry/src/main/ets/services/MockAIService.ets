import { Media } from '../models/Models';
import {
  AIClassification,
  FirstTimeSuggestion,
  GrowthMovieJob,
  NaturalCaptureResult
} from './AIService';
import {
  NaturalCaptureRequest,
  NaturalCaptureParseResult,
  NaturalCaptureItem,
  NaturalCaptureDomain,
  NaturalCaptureAction,
  JSONValue,
  jvString,
  jvNumber,
  jvArray
} from './NaturalCaptureDTO';
import { newUUID } from './AIService';

// MARK: - Mock AI 服务（对照 iOS Services/AI/MockAIService.swift）
// 接口先行：返回温暖、可信的假结果，让 AI 工坊在离线/预览时完整可玩。
// 正式部署调用 AIService（自托管 FastAPI），公共接口一致、UI 不改。

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), ms);
  });
}

export class MockAIService {
  static readonly shared = new MockAIService();
  private constructor() {}

  get isConfigured(): boolean {
    return true;
  }

  async ping(): Promise<boolean> {
    return true;
  }

  async classifyContent(note: string | undefined, tags: string[], locationName: string | undefined): Promise<AIClassification> {
    await sleep(400);
    return {
      suggestedTitle: '在家的午后',
      eventCluster: '日常',
      placeName: locationName ?? '家',
      visualTags: tags.length === 0 ? ['宝宝', '微笑', '室内'] : tags
    };
  }

  // 关键词假解析：离线/预览时让自然语言入口完整可玩。
  // 覆盖 6 个验收场景：疫苗、身高体重、餐食+喝水拆分、睡眠、不舒服、第一次；其余落普通时光。
  async parseNaturalCaptureFull(request: NaturalCaptureRequest): Promise<NaturalCaptureParseResult> {
    await sleep(500);
    const text = request.text;
    const items: NaturalCaptureItem[] = [];

    if (text.includes('疫苗')) {
      const fields: Record<string, JSONValue> = { 'vaccine_name': jvString('示例疫苗') };
      items.push(this.item(NaturalCaptureDomain.vaccine, '疫苗接种', undefined, fields, ['疫苗'], 0.9, true, text));
    }
    if (text.includes('身高') || text.includes('体重')) {
      const fields: Record<string, JSONValue> = { 'height_cm': jvNumber(82), 'weight_kg': jvNumber(10.6) };
      items.push(this.item(NaturalCaptureDomain.growth, '身高体重', undefined, fields, [], 0.88, false, text));
    }
    if (text.includes('吃')) {
      const fields: Record<string, JSONValue> = {
        'food_items': jvArray([jvString('南瓜米糊')]),
        'amount_text': jvString('半碗')
      };
      items.push(this.item(NaturalCaptureDomain.meal, '辅食餐', undefined, fields, ['辅食'], 0.9, false, text));
    }
    if (text.includes('喝水')) {
      const fields: Record<string, JSONValue> = { 'amount_ml': jvNumber(120) };
      items.push(this.item(NaturalCaptureDomain.water, '喝水', undefined, fields, [], 0.9, false, text));
    }
    if (text.includes('睡')) {
      const end = new Date();
      const start = new Date(end.getTime() - 10 * 60 * 60 * 1000);
      const fields: Record<string, JSONValue> = {
        'start_at': jvString(start.toISOString()),
        'end_at': jvString(end.toISOString())
      };
      const sleepItem = this.item(NaturalCaptureDomain.sleep, '睡眠', '中间醒了一次', fields, [], 0.86, false, text);
      sleepItem.date = end;
      items.push(sleepItem);
    }
    if (text.includes('咳嗽') || text.includes('发烧') || text.includes('不舒服') || text.includes('体温')) {
      const fields: Record<string, JSONValue> = {
        'symptoms': jvArray([jvString('咳嗽')]),
        'temperature_celsius': jvNumber(37.8)
      };
      items.push(this.item(NaturalCaptureDomain.symptom, '有点不舒服', undefined, fields, [], 0.85, true, text));
    }
    if (text.includes('第一次')) {
      const title = text.length > 16 ? text.substring(0, 16) : text;
      items.push(this.item(NaturalCaptureDomain.firstTime, title, text, {}, [], 0.84, false, text));
    }
    if (items.length === 0) {
      const title = text.length > 12 ? text.substring(0, 12) : text;
      items.push(this.item(NaturalCaptureDomain.timeline, title, text, {}, [], 0.7, false, text));
    }
    return { confidence: 0.85, items: items, warnings: [] };
  }

  // 简化版解析（对齐 AIService.parseNaturalCapture 的公共接口）。
  async parseNaturalCapture(text: string): Promise<NaturalCaptureResult> {
    await sleep(400);
    return { note: text, mood: undefined, domain: '日常' };
  }

  async detectFirstTime(media: Media[]): Promise<FirstTimeSuggestion | undefined> {
    await sleep(400);
    const tags: string[] = [];
    for (const m of media) {
      for (const t of m.aiTags) tags.push(t);
    }
    if (tags.includes('水果')) return { what: '第一次吃水果', confidence: 0.62 };
    if (tags.includes('蛋糕')) return { what: '第一次吃蛋糕', confidence: 0.7 };
    return undefined;
  }

  async transcribe(audioFilePath: string): Promise<string> {
    await sleep(600);
    return '（示例转写）布布在咿咿呀呀地说话，最后清楚地喊了一声「妈妈」。';
  }

  async rewriteFirstPerson(note: string, childName: string): Promise<string> {
    await sleep(1000);
    const trimmed = note.trim();
    const body = trimmed.length === 0 ? '小手摸到软软的光，耳边有熟悉的声音，我慢慢眨眨眼。' : trimmed;
    return `我是${childName}，这一刻有好多小感觉：${body}\n` +
      '我的小手动了动，眼睛也忙着看。身边的声音软软的，我好像把这一点点暖暖的东西，都悄悄装进心里了。';
  }

  async generateGrowthMovie(year: number): Promise<GrowthMovieJob> {
    await sleep(500);
    return { jobId: `mock-job-${year}`, year: year, status: 'generating' };
  }

  async movieNarration(year: number, childName: string, highlights: string[]): Promise<string> {
    const head = highlights.length > 3 ? highlights.slice(0, 3) : highlights;
    return `这是${childName}的一小段成长电影。` + head.join('，');
  }

  // 构造一条解析项（统一 date=now、id=UUID）。
  private item(
    domain: NaturalCaptureDomain,
    title: string,
    note: string | undefined,
    fields: Record<string, JSONValue>,
    tags: string[],
    confidence: number,
    needsConfirmation: boolean,
    sourceText: string
  ): NaturalCaptureItem {
    return {
      id: newUUID(),
      domain: domain,
      action: NaturalCaptureAction.create,
      title: title,
      note: note,
      date: new Date(),
      fields: fields,
      tags: tags,
      confidence: confidence,
      needsConfirmation: needsConfirmation,
      sourceText: sourceText
    };
  }
}

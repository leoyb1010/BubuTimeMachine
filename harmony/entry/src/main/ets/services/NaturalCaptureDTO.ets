// MARK: - 自然语言记录 解析 DTO（对照 iOS Services/AI/NaturalCaptureDTO.swift）
// 与 server/ai 的 /parse-natural-capture 对齐。写法与 DTOs.ets 保持一致（plain interface + 容错编解码）。
// 隐私：只发文字，不上传照片。

import { util } from '@kit.ArkTS';

// MARK: - 解析领域（对照 NaturalCaptureDomain）
// 解析失败/未知值时落到 unknown，不让一条坏数据毁掉整次解析（见 normalizeDomain）。
export enum NaturalCaptureDomain {
  vaccine = 'vaccine',
  growth = 'growth',
  meal = 'meal',
  snack = 'snack',
  supplement = 'supplement',
  water = 'water',
  sleep = 'sleep',
  symptom = 'symptom',
  checkup = 'checkup',
  timeline = 'timeline',
  milestone = 'milestone',
  firstTime = 'first_time',
  unknown = 'unknown'
}

// 兜底归一化：未知 raw → unknown（对照 NaturalCaptureDomain.init(from:)）。
export function normalizeDomain(raw: string | undefined): NaturalCaptureDomain {
  switch (raw) {
    case 'vaccine': return NaturalCaptureDomain.vaccine;
    case 'growth': return NaturalCaptureDomain.growth;
    case 'meal': return NaturalCaptureDomain.meal;
    case 'snack': return NaturalCaptureDomain.snack;
    case 'supplement': return NaturalCaptureDomain.supplement;
    case 'water': return NaturalCaptureDomain.water;
    case 'sleep': return NaturalCaptureDomain.sleep;
    case 'symptom': return NaturalCaptureDomain.symptom;
    case 'checkup': return NaturalCaptureDomain.checkup;
    case 'timeline': return NaturalCaptureDomain.timeline;
    case 'milestone': return NaturalCaptureDomain.milestone;
    case 'first_time': return NaturalCaptureDomain.firstTime;
    default: return NaturalCaptureDomain.unknown;
  }
}

// 显示名（对照 NaturalCaptureDomain.displayName）
export function domainDisplayName(d: NaturalCaptureDomain): string {
  switch (d) {
    case NaturalCaptureDomain.vaccine: return '疫苗';
    case NaturalCaptureDomain.growth: return '身高体重';
    case NaturalCaptureDomain.meal: return '餐食';
    case NaturalCaptureDomain.snack: return '零食';
    case NaturalCaptureDomain.supplement: return '营养补充';
    case NaturalCaptureDomain.water: return '喝水';
    case NaturalCaptureDomain.sleep: return '睡眠';
    case NaturalCaptureDomain.symptom: return '不舒服';
    case NaturalCaptureDomain.checkup: return '体检护理';
    case NaturalCaptureDomain.timeline: return '时光记录';
    case NaturalCaptureDomain.milestone: return '里程碑';
    case NaturalCaptureDomain.firstTime: return '第一次';
    case NaturalCaptureDomain.unknown: return '待分类';
    default: return '待分类';
  }
}

// SF Symbol 名（对照 NaturalCaptureDomain.icon；HarmonyOS 取用方按需映射成本地图标）
export function domainIcon(d: NaturalCaptureDomain): string {
  switch (d) {
    case NaturalCaptureDomain.vaccine: return 'syringe';
    case NaturalCaptureDomain.growth: return 'ruler';
    case NaturalCaptureDomain.meal: return 'fork.knife';
    case NaturalCaptureDomain.snack: return 'takeoutbag.and.cup.and.straw';
    case NaturalCaptureDomain.supplement: return 'pills';
    case NaturalCaptureDomain.water: return 'drop.fill';
    case NaturalCaptureDomain.sleep: return 'moon.zzz.fill';
    case NaturalCaptureDomain.symptom: return 'cross.case.fill';
    case NaturalCaptureDomain.checkup: return 'stethoscope';
    case NaturalCaptureDomain.timeline: return 'sparkles';
    case NaturalCaptureDomain.milestone: return 'star.fill';
    case NaturalCaptureDomain.firstTime: return 'party.popper';
    case NaturalCaptureDomain.unknown: return 'questionmark.circle';
    default: return 'questionmark.circle';
  }
}

// MARK: - 解析动作（对照 NaturalCaptureAction；未知 → create）
export enum NaturalCaptureAction {
  create = 'create',
  update = 'update',
  complete = 'complete'
}

export function normalizeAction(raw: string | undefined): NaturalCaptureAction {
  switch (raw) {
    case 'update': return NaturalCaptureAction.update;
    case 'complete': return NaturalCaptureAction.complete;
    default: return NaturalCaptureAction.create;
  }
}

// MARK: - JSONValue（对照 JSONValue enum，承载 fields 动态值）
// ArkTS 不支持联合枚举携带载荷，用 tagged interface 表达，并提供构造/取值辅助。
export enum JSONValueKind {
  string = 'string',
  number = 'number',
  bool = 'bool',
  array = 'array',
  object = 'object',
  null = 'null'
}

export interface JSONValue {
  kind: JSONValueKind;
  stringValue?: string;
  numberValue?: number;
  boolValue?: boolean;
  arrayValue?: JSONValue[];
  objectValue?: Record<string, JSONValue>;
}

// 构造辅助（对照 JSONValue 的 .string/.number/... 工厂）
export function jvString(v: string): JSONValue {
  return { kind: JSONValueKind.string, stringValue: v };
}
export function jvNumber(v: number): JSONValue {
  return { kind: JSONValueKind.number, numberValue: v };
}
export function jvBool(v: boolean): JSONValue {
  return { kind: JSONValueKind.bool, boolValue: v };
}
export function jvArray(v: JSONValue[]): JSONValue {
  return { kind: JSONValueKind.array, arrayValue: v };
}
export function jvObject(v: Record<string, JSONValue>): JSONValue {
  return { kind: JSONValueKind.object, objectValue: v };
}
export function jvNull(): JSONValue {
  return { kind: JSONValueKind.null };
}

// 把任意已解析 JSON 值（Object）转成 JSONValue（对照 JSONValue.init(from:)）。
export function jsonValueFrom(raw: Object | null | undefined): JSONValue {
  if (raw === null || raw === undefined) return jvNull();
  if (typeof raw === 'string') return jvString(raw as string);
  if (typeof raw === 'number') return jvNumber(raw as number);
  if (typeof raw === 'boolean') return jvBool(raw as boolean);
  if (Array.isArray(raw)) {
    const arr = raw as Object[];
    const out: JSONValue[] = [];
    for (const e of arr) out.push(jsonValueFrom(e));
    return jvArray(out);
  }
  // 其余视为对象
  const obj = raw as Record<string, Object>;
  const map: Record<string, JSONValue> = {};
  for (const key of Object.keys(obj)) {
    map[key] = jsonValueFrom(obj[key]);
  }
  return jvObject(map);
}

// MARK: - fields 取值辅助（对照 Dictionary where Value == JSONValue 的扩展）
export function fieldString(fields: Record<string, JSONValue>, key: string): string | undefined {
  const v = fields[key];
  if (v && v.kind === JSONValueKind.string) return v.stringValue;
  return undefined;
}

export function fieldDouble(fields: Record<string, JSONValue>, key: string): number | undefined {
  const v = fields[key];
  if (!v) return undefined;
  if (v.kind === JSONValueKind.number) return v.numberValue;
  if (v.kind === JSONValueKind.string && v.stringValue !== undefined) {
    const n = Number(v.stringValue);
    return Number.isNaN(n) ? undefined : n;
  }
  return undefined;
}

export function fieldStringArray(fields: Record<string, JSONValue>, key: string): string[] {
  const v = fields[key];
  if (!v || v.kind !== JSONValueKind.array || !v.arrayValue) return [];
  const out: string[] = [];
  for (const e of v.arrayValue) {
    if (e.kind === JSONValueKind.string && e.stringValue !== undefined) out.push(e.stringValue);
  }
  return out;
}

export function fieldISODate(fields: Record<string, JSONValue>, key: string): Date | undefined {
  const raw = fieldString(fields, key);
  if (raw === undefined) return undefined;
  return parseISODate(raw);
}

// MARK: - 请求 / 响应（对照 NaturalCaptureRequest / Result / Item）
// 日期统一用 ISO8601 字符串与服务端交换（happenedAt 等同 iOS Date 编码 .iso8601）。
export interface NaturalCaptureRequest {
  text: string;
  childName: string;
  timezone: string;
  referenceDate: string;   // ISO8601
}

export interface NaturalCaptureItem {
  id: string;              // UUID 字符串（对照 Identifiable id: UUID）
  domain: NaturalCaptureDomain;
  action: NaturalCaptureAction;
  title: string;
  note?: string;
  date?: Date;
  fields: Record<string, JSONValue>;
  tags: string[];
  confidence: number;
  needsConfirmation: boolean;
  sourceText: string;
}

// 与 iOS NaturalCaptureResult 同义（结构化建议结果）。
// 注意：服务层另有简化版 NaturalCaptureResult（note/mood/domain）供旧调用方使用，故此处命名为 ...Parse。
export interface NaturalCaptureParseResult {
  confidence: number;
  items: NaturalCaptureItem[];
  warnings: string[];
}

// App 端兜底：不完全相信 LLM。敏感 domain / 低置信度必须人工确认后才能入库。
// 对照 NaturalCaptureItem.requiresHardConfirmation。
export function requiresHardConfirmation(item: NaturalCaptureItem): boolean {
  if (item.needsConfirmation) return true;
  if (item.confidence < 0.82) return true;
  switch (item.domain) {
    case NaturalCaptureDomain.vaccine:
    case NaturalCaptureDomain.symptom:
    case NaturalCaptureDomain.supplement:
      return true;
    default:
      return false;
  }
}

// MARK: - 容错编解码（对照 NaturalCaptureCoding）
// ISO8601 容错解析：Date 构造已兼容带/不带小数秒的互联网时间；解析失败回 undefined。
export function parseISODate(raw: string): Date | undefined {
  const t = Date.parse(raw);
  if (!Number.isNaN(t)) return new Date(t);
  return undefined;
}

// 把 /parse-natural-capture 响应（已 JSON.parse 的对象）解码为 NaturalCaptureParseResult。
// 对照 NaturalCaptureCoding.decoder()：日期容错、domain/action 未知值兜底。
export function decodeParseResult(obj: Record<string, Object>): NaturalCaptureParseResult {
  const items: NaturalCaptureItem[] = [];
  const rawItems = obj['items'] as Record<string, Object>[] | undefined;
  if (rawItems) {
    for (const raw of rawItems) {
      items.push(decodeItem(raw));
    }
  }
  const warningsRaw = obj['warnings'] as Object[] | undefined;
  const warnings: string[] = [];
  if (warningsRaw) {
    for (const w of warningsRaw) {
      if (typeof w === 'string') warnings.push(w as string);
    }
  }
  return {
    confidence: numberOr(obj['confidence'], 0),
    items: items,
    warnings: warnings
  };
}

function decodeItem(raw: Record<string, Object>): NaturalCaptureItem {
  const fields: Record<string, JSONValue> = {};
  const rawFields = raw['fields'] as Record<string, Object> | undefined;
  if (rawFields) {
    for (const key of Object.keys(rawFields)) {
      fields[key] = jsonValueFrom(rawFields[key]);
    }
  }
  const tags: string[] = [];
  const rawTags = raw['tags'] as Object[] | undefined;
  if (rawTags) {
    for (const t of rawTags) {
      if (typeof t === 'string') tags.push(t as string);
    }
  }
  const dateRaw = raw['date'] as string | undefined;
  const idRaw = raw['id'] as string | undefined;
  return {
    id: (idRaw && idRaw.length > 0) ? idRaw : util.generateRandomUUID(true),
    domain: normalizeDomain(raw['domain'] as string | undefined),
    action: normalizeAction(raw['action'] as string | undefined),
    title: (raw['title'] as string | undefined) ?? '',
    note: raw['note'] as string | undefined,
    date: dateRaw ? parseISODate(dateRaw) : undefined,
    fields: fields,
    tags: tags,
    confidence: numberOr(raw['confidence'], 0),
    // CodingKeys: needs_confirmation / source_text
    needsConfirmation: (raw['needs_confirmation'] as boolean | undefined) ?? false,
    sourceText: (raw['source_text'] as string | undefined) ?? ''
  };
}

function numberOr(v: Object | undefined, def: number): number {
  if (typeof v === 'number') return v as number;
  if (typeof v === 'string') {
    const n = Number(v as string);
    return Number.isNaN(n) ? def : n;
  }
  return def;
}

// MARK: - 请求体序列化（fields → 原生 JSON，对照 JSONValue.encode）
export function encodeJSONValue(v: JSONValue): Object | null {
  switch (v.kind) {
    case JSONValueKind.string: return v.stringValue ?? '';
    case JSONValueKind.number: return v.numberValue ?? 0;
    case JSONValueKind.bool: return v.boolValue ?? false;
    case JSONValueKind.array: {
      const arr = v.arrayValue ?? [];
      const out: (Object | null)[] = [];
      for (const e of arr) {
        out.push(encodeJSONValue(e));
      }
      return out as Object;
    }
    case JSONValueKind.object: {
      const map = v.objectValue ?? {};
      const out: Record<string, Object | null> = {};
      for (const key of Object.keys(map)) {
        out[key] = encodeJSONValue(map[key]);
      }
      return out as Object;
    }
    case JSONValueKind.null: return null;
    default: return null;
  }
}

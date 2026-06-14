import { util } from '@kit.ArkTS';
import { AppDatabase } from '../data/AppDatabase';
import {
  HealthRecord, VaccineRecord, GrowthMeasurement, Milestone, FirstTime, Entry, FeedEvent
} from '../models/Models';
import { SyncState, HealthRecordKind, FeedEventKind, healthKindMeta } from '../models/Enums';
import {
  NaturalCaptureItem, NaturalCaptureDomain,
  fieldString, fieldDouble, fieldStringArray, fieldISODate
} from '../services/NaturalCaptureDTO';

// MARK: - 自然语言记录 → 各模块落库路由（对照 iOS Features/NaturalCapture/NaturalCaptureRouter.swift）
// LLM 解析结果经用户确认后，由这里写入对应模型并产生 FeedEvent。
// 原则：不确定就降级为普通时光记录，绝不编造字段。
export class NaturalCaptureRouter {
  // 解耦 AppEnvironment：只需要作者角色字符串（对照 authorRole）。
  private authorRole: string;

  constructor(authorRole: string) {
    this.authorRole = authorRole;
  }

  // 对照 save(_ item:)：按 domain 分流。
  async save(item: NaturalCaptureItem): Promise<void> {
    switch (item.domain) {
      case NaturalCaptureDomain.vaccine:
        await this.saveVaccine(item);
        break;
      case NaturalCaptureDomain.growth:
        await this.saveGrowth(item);
        break;
      case NaturalCaptureDomain.meal:
        await this.saveHealth(item, HealthRecordKind.meal);
        break;
      case NaturalCaptureDomain.snack:
        await this.saveHealth(item, HealthRecordKind.snack);
        break;
      case NaturalCaptureDomain.supplement:
        await this.saveHealth(item, HealthRecordKind.supplement);
        break;
      case NaturalCaptureDomain.water:
        await this.saveHealth(item, HealthRecordKind.water);
        break;
      case NaturalCaptureDomain.sleep:
        await this.saveHealth(item, HealthRecordKind.sleep);
        break;
      case NaturalCaptureDomain.symptom:
        await this.saveHealth(item, HealthRecordKind.symptom);
        break;
      case NaturalCaptureDomain.checkup:
        await this.saveHealth(item, HealthRecordKind.checkup);
        break;
      case NaturalCaptureDomain.milestone:
        await this.saveMilestone(item);
        break;
      case NaturalCaptureDomain.firstTime:
        await this.saveFirstTime(item);
        break;
      case NaturalCaptureDomain.timeline:
      case NaturalCaptureDomain.unknown:
      default:
        await this.saveEntry(item);
        break;
    }
  }

  // 事件时间（对照 item.date ?? .now）→ epoch ms。
  private dateMs(item: NaturalCaptureItem): number {
    return item.date !== undefined ? item.date.getTime() : Date.now();
  }

  // 写一条家庭动态（对照 context.insert(FeedEvent(...))）。
  private async addFeed(kind: FeedEventKind, summary: string, targetLocalId?: string): Promise<void> {
    const now = Date.now();
    const ev: FeedEvent = {
      id: util.generateRandomUUID(true),
      kind: kind,
      actorRole: this.authorRole,
      summary: summary,
      targetLocalId: targetLocalId,
      happenedAt: now,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertFeedEvent(ev);
  }

  // MARK: 健康记录（对照 saveHealth）

  private async saveHealth(item: NaturalCaptureItem, kind: HealthRecordKind): Promise<void> {
    const now = Date.now();
    const tags: string[] = item.tags.slice();
    const record: HealthRecord = {
      id: util.generateRandomUUID(true),
      kind: kind,
      title: item.title,
      detail: item.note,
      recordedAt: this.dateMs(item),
      tags: tags,
      syncState: SyncState.local,
      createdAt: now
    };

    switch (kind) {
      case HealthRecordKind.water: {
        const ml = fieldDouble(item.fields, 'amount_ml');
        if (ml !== undefined) {
          record.amountValue = ml;
          record.amountUnit = 'ml';
          record.amountText = `${Math.trunc(ml)}ml`;
        }
        break;
      }
      case HealthRecordKind.sleep: {
        // HealthRecord 自有 startAt/endAt：优先落区间，时长仅兜底。
        const start = fieldISODate(item.fields, 'start_at');
        const end = fieldISODate(item.fields, 'end_at');
        record.startAt = start !== undefined ? start.getTime() : undefined;
        record.endAt = end !== undefined ? end.getTime() : undefined;
        if (record.startAt === undefined && record.endAt === undefined) {
          const minutes = fieldDouble(item.fields, 'duration_minutes');
          if (minutes !== undefined) {
            record.amountValue = minutes / 60;
            record.amountUnit = '小时';
          }
        }
        const quality = fieldString(item.fields, 'quality');
        if (quality !== undefined && record.detail === undefined) {
          record.detail = quality;
        }
        break;
      }
      case HealthRecordKind.symptom: {
        record.temperatureCelsius = fieldDouble(item.fields, 'temperature_celsius');
        record.tags = record.tags.concat(fieldStringArray(item.fields, 'symptoms'));
        break;
      }
      case HealthRecordKind.meal:
      case HealthRecordKind.snack: {
        const foods = fieldStringArray(item.fields, 'food_items');
        if (foods.length > 0) record.tags = record.tags.concat(foods);
        record.amountText = fieldString(item.fields, 'amount_text');
        record.reaction = fieldString(item.fields, 'reaction');
        break;
      }
      case HealthRecordKind.supplement: {
        record.amountText = fieldString(item.fields, 'amount_text');
        const name = fieldString(item.fields, 'supplement_name');
        if (name !== undefined) record.tags.push(name);
        break;
      }
      case HealthRecordKind.checkup: {
        if (record.detail === undefined) record.detail = fieldString(item.fields, 'note');
        break;
      }
      default:
        break;
    }

    await AppDatabase.shared.insertHealth(record);
    await this.addFeed(FeedEventKind.healthRecorded,
      `智能记录了${healthKindMeta(kind).title}：${record.title}`);
  }

  // MARK: 疫苗（结构化 VaccineRecord）（对照 saveVaccine）
  // NOTE: iOS 会按国家排期 VaccineDose.schedule 匹配剂次（matchDose）；本切片未携带排期表，
  // 故仅落自由疫苗记录，doseId/doseLabel 保留来自 LLM 字段，行为等价于「匹配不到剂次」分支。
  private async saveVaccine(item: NaturalCaptureItem): Promise<void> {
    const now = Date.now();
    const name = fieldString(item.fields, 'vaccine_name') ?? item.title;
    const record: VaccineRecord = {
      id: util.generateRandomUUID(true),
      vaccineName: name,
      injectedAt: this.dateMs(item),
      doseLabel: fieldString(item.fields, 'dose_label'),
      hospital: fieldString(item.fields, 'hospital'),
      injectionSite: fieldString(item.fields, 'injection_site'),
      reaction: fieldString(item.fields, 'reaction'),
      note: item.note,
      source: 'ai',
      syncState: SyncState.local,
      createdAt: now,
      updatedAt: now
    };
    await AppDatabase.shared.insertVaccine(record);
    await this.addFeed(FeedEventKind.healthRecorded, `智能记录了疫苗接种：${name}`);
  }

  // MARK: 成长测量（结构化 GrowthMeasurement）（对照 saveGrowth）
  private async saveGrowth(item: NaturalCaptureItem): Promise<void> {
    const now = Date.now();
    const height = fieldDouble(item.fields, 'height_cm');
    const weight = fieldDouble(item.fields, 'weight_kg');
    const head = fieldDouble(item.fields, 'head_circumference_cm');
    // 三项皆空 → 降级为体检护理记录（对照 guard ... else saveHealth(.checkup)）。
    if (height === undefined && weight === undefined && head === undefined) {
      await this.saveHealth(item, HealthRecordKind.checkup);
      return;
    }
    const measurement: GrowthMeasurement = {
      id: util.generateRandomUUID(true),
      measuredAt: this.dateMs(item),
      heightCm: height,
      weightKg: weight,
      headCircumferenceCm: head,
      note: item.note,
      source: 'ai',
      syncState: SyncState.local,
      createdAt: now,
      updatedAt: now
    };
    await AppDatabase.shared.insertGrowth(measurement);
    await this.addFeed(FeedEventKind.healthRecorded, `智能记录了成长测量：${item.title}`);
  }

  // MARK: 里程碑（对照 saveMilestone；低置信降级为时光）
  private async saveMilestone(item: NaturalCaptureItem): Promise<void> {
    if (item.confidence < 0.6) {
      await this.saveEntry(item);
      return;
    }
    const now = Date.now();
    const milestone: Milestone = {
      id: util.generateRandomUUID(true),
      title: item.title,
      category: '认知探索',
      emoji: '⭐',
      detail: item.note,
      happenedAt: this.dateMs(item),
      isCustom: true,
      ceremonyPlayed: false,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.upsertMilestone(milestone);
    await this.addFeed(FeedEventKind.milestoneLit, `智能点亮了里程碑：${item.title}`);
  }

  // MARK: 第一次（对照 saveFirstTime；低置信降级为时光）
  private async saveFirstTime(item: NaturalCaptureItem): Promise<void> {
    if (item.confidence < 0.6) {
      await this.saveEntry(item);
      return;
    }
    const now = Date.now();
    const first: FirstTime = {
      id: util.generateRandomUUID(true),
      what: item.title,
      detectedByAI: true,
      confirmedByParent: true,
      ceremonyPlayed: false,
      happenedAt: this.dateMs(item),
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertFirstTime(first);
    await this.addFeed(FeedEventKind.firstTimeConfirmed, `智能记下了「${item.title}」`);
  }

  // MARK: 普通时光（对照 saveEntry）
  private async saveEntry(item: NaturalCaptureItem): Promise<void> {
    const now = Date.now();
    const entry: Entry = {
      id: util.generateRandomUUID(true),
      happenedAt: this.dateMs(item),
      authorRole: this.authorRole,
      note: item.note ?? item.sourceText,
      title: item.title,
      syncState: SyncState.local,
      isArchived: false,
      createdAt: now
    };
    await AppDatabase.shared.insertEntry(entry);
    await this.addFeed(FeedEventKind.entryCreated, `智能记录了一条时光：${item.title}`, entry.id);
  }
}

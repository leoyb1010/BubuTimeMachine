import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AppDatabase } from '../data/AppDatabase';
import { VaccineRecord } from '../models/Models';
import { SyncState } from '../models/Enums';

const DOMAIN = 0x0000;

// MARK: - 旧版疫苗打卡迁移（对照 iOS Services/Sync/VaccineLegacyMigrator.swift）
// @AppStorage("bubu.vaccine.done") JSON 数组（doseId 列表）→ 结构化 VaccineRecord，一次性执行。
// 幂等：migrated 标记防重入；保留旧键以便回滚；接种日取排期 dueDate（不晚于今天），note 标注待确认。
// NOTE: Harmony 端无独立 VaccineSchedule 文件，按 iOS VaccineSchedule.swift 内置同一份排期表（一类苗）。

// 单条剂次排期（对照 iOS VaccineDose）。
interface VaccineDose {
  id: string;          // 稳定 id：疫苗简称+剂次
  vaccine: string;     // 疫苗全称
  doseLabel: string;   // 第几剂
  monthDue: number;    // 推荐接种月龄（出生为 0）
}

export class VaccineLegacyMigrator {
  static readonly migratedKey: string = 'bubu.vaccine.migrated';
  static readonly legacyKey: string = 'bubu.vaccine.done';

  // 国家免疫规划疫苗排期表（一类苗，对照 iOS VaccineDose.schedule，字段精简到迁移所需）。
  private static readonly schedule: VaccineDose[] = [
    { id: 'HepB-1', vaccine: '乙肝疫苗', doseLabel: '第1剂', monthDue: 0 },
    { id: 'BCG-1', vaccine: '卡介苗', doseLabel: '第1剂', monthDue: 0 },
    { id: 'HepB-2', vaccine: '乙肝疫苗', doseLabel: '第2剂', monthDue: 1 },
    { id: 'IPV-1', vaccine: '脊灰灭活疫苗', doseLabel: '第1剂', monthDue: 2 },
    { id: 'DTaP-1', vaccine: '百白破疫苗', doseLabel: '第1剂', monthDue: 3 },
    { id: 'IPV-2', vaccine: '脊灰灭活疫苗/二价', doseLabel: '第2剂', monthDue: 3 },
    { id: 'DTaP-2', vaccine: '百白破疫苗', doseLabel: '第2剂', monthDue: 4 },
    { id: 'OPV-3', vaccine: '脊灰减毒活疫苗', doseLabel: '第3剂', monthDue: 4 },
    { id: 'DTaP-3', vaccine: '百白破疫苗', doseLabel: '第3剂', monthDue: 5 },
    { id: 'HepB-3', vaccine: '乙肝疫苗', doseLabel: '第3剂', monthDue: 6 },
    { id: 'MenA-1', vaccine: 'A群流脑多糖疫苗', doseLabel: '第1剂', monthDue: 6 },
    { id: 'MenA-2', vaccine: 'A群流脑多糖疫苗', doseLabel: '第2剂', monthDue: 9 },
    { id: 'MMR-1', vaccine: '麻腮风疫苗', doseLabel: '第1剂', monthDue: 8 },
    { id: 'JE-1', vaccine: '乙脑减毒活疫苗', doseLabel: '第1剂', monthDue: 8 },
    { id: 'MMR-2', vaccine: '麻腮风疫苗', doseLabel: '第2剂', monthDue: 18 },
    { id: 'DTaP-4', vaccine: '百白破疫苗', doseLabel: '第4剂', monthDue: 18 },
    { id: 'HepA-1', vaccine: '甲肝减毒活疫苗', doseLabel: '第1剂', monthDue: 18 },
    { id: 'JE-2', vaccine: '乙脑减毒活疫苗', doseLabel: '第2剂', monthDue: 24 },
    { id: 'MenAC-1', vaccine: 'A群C群流脑多糖疫苗', doseLabel: '第3剂', monthDue: 36 },
    { id: 'DTaP-5', vaccine: '白破疫苗', doseLabel: '加强', monthDue: 72 },
    { id: 'OPV-4', vaccine: '脊灰减毒活疫苗', doseLabel: '第4剂', monthDue: 48 },
    { id: 'MenAC-2', vaccine: 'A群C群流脑多糖疫苗', doseLabel: '第4剂', monthDue: 72 }
  ];

  // 推荐接种日期（生日 + monthDue 个月，对照 iOS dueDate(birthday:)）。
  private static dueDate(birthdayMs: number, monthDue: number): number {
    const d = new Date(birthdayMs);
    d.setMonth(d.getMonth() + monthDue);
    return d.getTime();
  }

  // 幂等迁移：migrated 标记防重入；旧键为 doseId 字符串数组（对照 iOS migrateIfNeeded）。
  static async migrateIfNeeded(context: common.UIAbilityContext): Promise<void> {
    const store = await preferences.getPreferences(context, 'bubu_vaccine_migration');
    const migrated = await store.get(VaccineLegacyMigrator.migratedKey, false) as boolean;
    if (migrated) return;

    try {
      const raw = await store.get(VaccineLegacyMigrator.legacyKey, '') as string;
      if (raw.length === 0) return;
      let doseIds: string[] = [];
      try {
        const parsed = JSON.parse(raw) as Object;
        if (Array.isArray(parsed)) {
          doseIds = (parsed as Object[]).map((x) => `${x}`);
        }
      } catch (e) {
        return;
      }
      if (doseIds.length === 0) return;

      // 已有记录的 doseId 集合，避免重复插入。
      const existing = await AppDatabase.shared.fetchVaccines();
      const existingDoseIds = new Set<string>();
      for (const v of existing) { if (v.doseId !== undefined) existingDoseIds.add(v.doseId); }

      const profile = await AppDatabase.shared.fetchChildProfile();
      const birthdayMs = profile ? profile.birthday : Date.now();
      const now = Date.now();

      for (const doseId of doseIds) {
        if (existingDoseIds.has(doseId)) continue;
        const dose = VaccineLegacyMigrator.schedule.find((d) => d.id === doseId);
        if (!dose) continue;
        const due = profile ? VaccineLegacyMigrator.dueDate(birthdayMs, dose.monthDue) : now;
        const injectedAt = Math.min(due, now); // 接种日不晚于今天（对照 iOS min(due, .now)）
        const record: VaccineRecord = {
          id: util.generateRandomUUID(true),
          doseId: dose.id,
          vaccineName: dose.vaccine,
          doseLabel: dose.doseLabel,
          injectedAt: injectedAt,
          note: '从旧版打卡迁移，具体接种日期请家长确认',
          source: 'migration',
          syncState: SyncState.local,
          createdAt: now,
          updatedAt: now
        };
        await AppDatabase.shared.insertVaccine(record);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `疫苗迁移失败: ${JSON.stringify(e)}`);
    } finally {
      // defer：无论成败都打标记，防重入（对照 iOS defer { defaults.set(true) }）。
      await store.put(VaccineLegacyMigrator.migratedKey, true);
      await store.flush();
    }
  }
}

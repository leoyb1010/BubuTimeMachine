// MARK: - VaccineSchedule（对照 iOS Features/Health/VaccineSchedule.swift）
// 内置中国国家免疫规划程序（一类苗，免费）按月龄排期。无网络依赖。
// 用于按布布月龄自动排期 + 完成打卡 + 提前提醒。仅供家庭参考，以当地接种点通知为准。

// 一个排期剂次（对照 iOS struct VaccineDose）。
export interface VaccineDose {
  id: string;          // 稳定 id：疫苗简称+剂次
  vaccine: string;     // 疫苗全称
  shortName: string;   // 简称
  doseLabel: string;   // 第几剂
  monthDue: number;    // 推荐接种月龄（出生为 0）
  prevents: string;    // 预防疾病
}

// 国家免疫规划疫苗排期表（对照 iOS VaccineDose.schedule）。
export const VACCINE_SCHEDULE: VaccineDose[] = [
  { id: 'HepB-1', vaccine: '乙肝疫苗', shortName: '乙肝', doseLabel: '第1剂', monthDue: 0, prevents: '乙型肝炎' },
  { id: 'BCG-1', vaccine: '卡介苗', shortName: '卡介苗', doseLabel: '第1剂', monthDue: 0, prevents: '结核病' },
  { id: 'HepB-2', vaccine: '乙肝疫苗', shortName: '乙肝', doseLabel: '第2剂', monthDue: 1, prevents: '乙型肝炎' },
  { id: 'IPV-1', vaccine: '脊灰灭活疫苗', shortName: '脊灰', doseLabel: '第1剂', monthDue: 2, prevents: '脊髓灰质炎' },
  { id: 'DTaP-1', vaccine: '百白破疫苗', shortName: '百白破', doseLabel: '第1剂', monthDue: 3, prevents: '百日咳/白喉/破伤风' },
  { id: 'IPV-2', vaccine: '脊灰灭活疫苗/二价', shortName: '脊灰', doseLabel: '第2剂', monthDue: 3, prevents: '脊髓灰质炎' },
  { id: 'DTaP-2', vaccine: '百白破疫苗', shortName: '百白破', doseLabel: '第2剂', monthDue: 4, prevents: '百日咳/白喉/破伤风' },
  { id: 'OPV-3', vaccine: '脊灰减毒活疫苗', shortName: '脊灰', doseLabel: '第3剂', monthDue: 4, prevents: '脊髓灰质炎' },
  { id: 'DTaP-3', vaccine: '百白破疫苗', shortName: '百白破', doseLabel: '第3剂', monthDue: 5, prevents: '百日咳/白喉/破伤风' },
  { id: 'HepB-3', vaccine: '乙肝疫苗', shortName: '乙肝', doseLabel: '第3剂', monthDue: 6, prevents: '乙型肝炎' },
  { id: 'MenA-1', vaccine: 'A群流脑多糖疫苗', shortName: '流脑A', doseLabel: '第1剂', monthDue: 6, prevents: '流行性脑脊髓膜炎' },
  { id: 'MenA-2', vaccine: 'A群流脑多糖疫苗', shortName: '流脑A', doseLabel: '第2剂', monthDue: 9, prevents: '流行性脑脊髓膜炎' },
  { id: 'MMR-1', vaccine: '麻腮风疫苗', shortName: '麻腮风', doseLabel: '第1剂', monthDue: 8, prevents: '麻疹/腮腺炎/风疹' },
  { id: 'JE-1', vaccine: '乙脑减毒活疫苗', shortName: '乙脑', doseLabel: '第1剂', monthDue: 8, prevents: '流行性乙型脑炎' },
  { id: 'MMR-2', vaccine: '麻腮风疫苗', shortName: '麻腮风', doseLabel: '第2剂', monthDue: 18, prevents: '麻疹/腮腺炎/风疹' },
  { id: 'DTaP-4', vaccine: '百白破疫苗', shortName: '百白破', doseLabel: '第4剂', monthDue: 18, prevents: '百日咳/白喉/破伤风' },
  { id: 'HepA-1', vaccine: '甲肝减毒活疫苗', shortName: '甲肝', doseLabel: '第1剂', monthDue: 18, prevents: '甲型肝炎' },
  { id: 'JE-2', vaccine: '乙脑减毒活疫苗', shortName: '乙脑', doseLabel: '第2剂', monthDue: 24, prevents: '流行性乙型脑炎' },
  { id: 'MenAC-1', vaccine: 'A群C群流脑多糖疫苗', shortName: '流脑AC', doseLabel: '第3剂', monthDue: 36, prevents: '流行性脑脊髓膜炎' },
  { id: 'DTaP-5', vaccine: '白破疫苗', shortName: '白破', doseLabel: '加强', monthDue: 72, prevents: '白喉/破伤风' },
  { id: 'OPV-4', vaccine: '脊灰减毒活疫苗', shortName: '脊灰', doseLabel: '第4剂', monthDue: 48, prevents: '脊髓灰质炎' },
  { id: 'MenAC-2', vaccine: 'A群C群流脑多糖疫苗', shortName: '流脑AC', doseLabel: '第4剂', monthDue: 72, prevents: '流行性脑脊髓膜炎' }
];

// 推荐接种的大致日期（基于生日 + monthDue，epoch ms）。对照 iOS dueDate(birthday:)。
export function vaccineDueDate(dose: VaccineDose, birthdayMs: number): number {
  const d = new Date(birthdayMs);
  // 对齐 Swift Calendar.date(byAdding: .month)：按日历月推进。
  const result = new Date(d.getFullYear(), d.getMonth() + dose.monthDue, d.getDate(),
    d.getHours(), d.getMinutes(), d.getSeconds());
  return result.getTime();
}

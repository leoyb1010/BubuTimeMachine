// MARK: - 年龄计算（逐行对照 iOS Models/AgeCalculator.swift）
// 布布生日驱动全 App 的年龄展示。纯函数、无副作用，可被 UI / 卡片 / 意图复用。

export class AgeCalculator {
  // 精确年龄描述："1岁11个月" / "出生第3天" / "还有N天出生"
  static ageDescription(birthdayMs: number, atMs: number): string {
    if (atMs < birthdayMs) {
      const days = AgeCalculator.dayDiff(atMs, birthdayMs);
      return days <= 0 ? '即将出生' : `还有${days}天出生`;
    }
    const c = AgeCalculator.ymd(birthdayMs, atMs);
    if (c.y === 0 && c.m === 0) {
      return c.d === 0 ? '出生当天' : `出生第${c.d}天`;
    }
    if (c.y === 0) {
      return c.d === 0 ? `${c.m}个月` : `${c.m}个月${c.d}天`;
    }
    if (c.m === 0) {
      return c.d === 0 ? `${c.y}岁` : `${c.y}岁${c.d}天`;
    }
    return `${c.y}岁${c.m}个月`;
  }

  // 来到世界第几天（出生当天算第 1 天）
  static daysSinceBirth(birthdayMs: number, atMs: number = Date.now()): number {
    const days = AgeCalculator.dayDiff(AgeCalculator.startOfDay(birthdayMs), AgeCalculator.startOfDay(atMs));
    return Math.max(0, days) + 1;
  }

  // 当前第几岁（0 = 未满 1 岁）
  static ageYears(birthdayMs: number, atMs: number = Date.now()): number {
    return Math.max(0, AgeCalculator.ymd(birthdayMs, atMs).y);
  }

  // 紧凑年龄："1岁11月" / "23天"
  static compactAge(birthdayMs: number, atMs: number): string {
    if (atMs < birthdayMs) return '孕期';
    const c = AgeCalculator.ymd(birthdayMs, atMs);
    if (c.y === 0 && c.m === 0) return `${c.d}天`;
    if (c.y === 0) return `${c.m}月`;
    return c.m === 0 ? `${c.y}岁` : `${c.y}岁${c.m}月`;
  }

  // 距下个生日还有几天
  static daysUntilNextBirthday(birthdayMs: number, fromMs: number = Date.now()): number {
    const bd = new Date(birthdayMs);
    const from = new Date(fromMs);
    let next = new Date(from.getFullYear(), bd.getMonth(), bd.getDate());
    const startFrom = AgeCalculator.startOfDay(fromMs);
    if (next.getTime() <= startFrom) {
      next = new Date(from.getFullYear() + 1, bd.getMonth(), bd.getDate());
    }
    return AgeCalculator.dayDiff(startFrom, next.getTime());
  }

  // —— 工具 ——
  private static startOfDay(ms: number): number {
    const d = new Date(ms);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  }

  private static dayDiff(fromMs: number, toMs: number): number {
    return Math.round((toMs - fromMs) / 86400000);
  }

  // 历法 年/月/日 差（按日历分量，对齐 Swift Calendar.dateComponents）
  private static ymd(fromMs: number, toMs: number): YMD {
    const f = new Date(fromMs);
    const t = new Date(toMs);
    let y = t.getFullYear() - f.getFullYear();
    let m = t.getMonth() - f.getMonth();
    let d = t.getDate() - f.getDate();
    if (d < 0) {
      m -= 1;
      // 上个月的天数
      const prevMonth = new Date(t.getFullYear(), t.getMonth(), 0).getDate();
      d += prevMonth;
    }
    if (m < 0) {
      y -= 1;
      m += 12;
    }
    return { y, m, d };
  }
}

interface YMD {
  y: number;
  m: number;
  d: number;
}

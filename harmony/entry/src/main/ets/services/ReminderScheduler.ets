import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/AppDatabase';
import { AgeCalculator } from '../models/AgeCalculator';
import type { Entry, ChildProfile } from '../models/Models';
import { VACCINE_SCHEDULE, VaccineDose, vaccineDueDate } from '../view/VaccineSchedule';

const DOMAIN = 0x0000;

interface UpcomingVaccineReminder {
  dose: VaccineDose;
  due: number;
  index: number;
}

// MARK: - 那年今日 · 提醒调度（对照 iOS Services/ReminderScheduler.swift）
// 每天上午 9:00 提醒一次：往年的今天，布布在做什么；同时安排最近疫苗的提前 3 天和到期提醒。
//
// iOS 用 UserNotifications(UNUserNotificationCenter + UNCalendarNotificationTrigger)；
// HarmonyOS 用 @ohos.reminderAgentManager(reminderAgentManager) 发布日历型定时提醒（CALENDAR），
// 授权用 @kit.NotificationKit notificationManager.requestEnableNotification。
// Reminder Agent 的 reminderId 不是跨进程稳定标识，因此每次刷新先撤销本应用全部提醒，再统一重排，
// 避免重启后旧提醒无法撤销或重复发布。
export class ReminderScheduler {
  static readonly shared = new ReminderScheduler();

  // iOS: private let identifierPrefix / daysAhead
  private readonly daysAhead: number = 30;

  private constructor() {}

  // iOS: func update(enabled:context:) async
  // 开关变化时调用。开 → 申请授权后重排未来 7 天；关 → 撤销全部待发提醒。
  async update(enabled: boolean): Promise<void> {
    if (enabled) {
      const granted = await this.requestAuthorization();
      if (!granted) return;
    }
    await this.refreshAll(enabled);
  }

  // iOS: func refreshIfEnabled(enabled:context:)
  // App 启动时按开关状态刷新（滚动重排未来 7 天）。
  async refreshIfEnabled(enabled: boolean): Promise<void> {
    await this.refreshAll(enabled);
  }

  async refreshAll(dailyEnabled: boolean): Promise<void> {
    await reminderAgentManager.cancelAllReminders();
    if (!(await notificationManager.isNotificationEnabled())) return;
    if (dailyEnabled) await this.scheduleDailyMemories();
    await this.scheduleVaccineReminders();
  }

  // iOS: center.requestAuthorization(options: [.alert, .sound, .badge])
  private async requestAuthorization(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification();
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `通知授权失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // iOS: private func scheduleWeekAhead(center:context:)
  // 先清掉旧的（连旧版单条重复一并撤销），再为未来 7 天各排一条 9:00 的日历提醒。
  private async scheduleDailyMemories(): Promise<void> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false); // 已按 happenedAt 倒序、排除归档
    const now = Date.now();

    for (let offset = 0; offset < this.daysAhead; offset++) {
      // iOS: cal.date(byAdding:.day, value: offset, to:.now)
      const day = new Date(now + offset * 86400000);
      // 该天的 9:00（本地）。今天 9 点已过则跳过今天（对齐 iOS fireDate <= .now continue）。
      const fire = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 9, 0, 0, 0);
      if (fire.getTime() <= now) continue;

      const memory = this.onThisDayMemory(entries, profile, day);
      const body = memory.length === 0
        ? '翻一翻布布的时光轴，今天也想她了吧。'
        : memory;

      // iOS: UNCalendarNotificationTrigger(dateMatching: comps, repeats:false)
      // HarmonyOS: ReminderRequestCalendar 指定具体年月日时分（一次性，不重复）。
      const reminder: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: fire.getFullYear(),
          month: fire.getMonth() + 1, // HarmonyOS month 为 1...12
          day: fire.getDate(),
          hour: 9,
          minute: 0,
          second: 0
        },
        title: '那年今日 · 布布时光机',
        content: body,
        wantAgent: {
          pkgName: 'com.bubu.timemachine',
          abilityName: 'EntryAbility',
          parameters: { 'bubuReminderDraft': '今天的布布……' }
        },
        notificationId: 9100 + offset,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };

      try {
        await reminderAgentManager.publishReminder(reminder);
      } catch (e) {
        hilog.error(DOMAIN, 'Bubu', `发布提醒失败 offset=${offset}: ${JSON.stringify(e)}`);
      }
    }
  }

  private async scheduleVaccineReminders(): Promise<void> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    if (!profile) return;
    const records = await AppDatabase.shared.fetchVaccines();
    const completed = new Set<string>();
    for (const record of records) {
      if (record.doseId) completed.add(record.doseId);
    }

    const now = Date.now();
    const startToday = ReminderScheduler.startOfDay(now);
    const upcoming: UpcomingVaccineReminder[] = [];
    for (let index = 0; index < VACCINE_SCHEDULE.length; index++) {
      const dose = VACCINE_SCHEDULE[index];
      if (completed.has(dose.id)) continue;
      const due = vaccineDueDate(dose, profile.birthday);
      const days = Math.round((ReminderScheduler.startOfDay(due) - startToday) / 86400000);
      if (days >= -14 && days <= 60) {
        const item: UpcomingVaccineReminder = { dose: dose, due: due, index: index };
        upcoming.push(item);
      }
    }
    upcoming.sort((a, b) => a.due - b.due);

    for (const item of upcoming.slice(0, 3)) {
      const name = `${item.dose.vaccine}·${item.dose.doseLabel}`;
      const dueText = ReminderScheduler.dateText(item.due);
      const pre = new Date(item.due);
      pre.setDate(pre.getDate() - 3);
      pre.setHours(9, 31, 0, 0);
      if (pre.getTime() > now) {
        await this.publishCalendar(pre, 9200 + item.index * 2,
          '疫苗预告 💉', `「${name}」预计 ${dueText} 到期（${item.dose.prevents}）。可以先约接种点啦～`,
          `准备给布布接种${name}，`);
      }
      const due = new Date(item.due);
      due.setHours(9, 31, 0, 0);
      if (due.getTime() > now) {
        await this.publishCalendar(due, 9201 + item.index * 2,
          '今天该打疫苗啦 💉', `「${name}」今天到期（${item.dose.prevents}）。打完回到布布时光机记上～`,
          `今天布布接种了${name}，`);
      }
    }
  }

  private async publishCalendar(fire: Date, notificationId: number, title: string, content: string,
                                draft: string): Promise<void> {
    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: fire.getFullYear(), month: fire.getMonth() + 1, day: fire.getDate(),
        hour: fire.getHours(), minute: fire.getMinutes(), second: 0
      },
      title: title,
      content: content,
      wantAgent: {
        pkgName: 'com.bubu.timemachine', abilityName: 'EntryAbility',
        parameters: { 'bubuReminderDraft': draft }
      },
      notificationId: notificationId,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    };
    try {
      await reminderAgentManager.publishReminder(reminder);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `发布提醒失败 notificationId=${notificationId}: ${JSON.stringify(e)}`);
    }
  }

  private static startOfDay(ms: number): number {
    const date = new Date(ms);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  private static dateText(ms: number): string {
    const date = new Date(ms);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }

  // iOS: private func onThisDayMemory(context:for:) -> String
  // 取指定日期「往年同月同日」的一条记录摘要。entries 已按 happenedAt 倒序传入。
  private onThisDayMemory(entries: Entry[], profile: ChildProfile | null, day: Date): string {
    const targetMonth = day.getMonth();
    const targetDay = day.getDate();

    for (const e of entries) {
      const ed = new Date(e.happenedAt);
      // 同月同日，且不是 day 当天（往年）。对齐 iOS pastYear = !isSameDay。
      const sameMonthDay = ed.getMonth() === targetMonth && ed.getDate() === targetDay;
      const isSameDay = ed.getFullYear() === day.getFullYear()
        && ed.getMonth() === day.getMonth()
        && ed.getDate() === day.getDate();
      if (sameMonthDay && !isSameDay) {
        // iOS: cal.dateComponents([.year], from: e.happenedAt, to: day).year —— 整年差。
        const years = ReminderScheduler.wholeYearsBetween(e.happenedAt, day.getTime());
        const age = profile
          ? AgeCalculator.ageDescription(profile.birthday, e.happenedAt)
          : '';
        const note = (e.note && e.note.length > 0) ? e.note : '那天的布布';
        return years > 0
          ? `${years}年前的今天（${age}）：${note}`
          : `那年今日（${age}）：${note}`;
      }
    }
    return '';
  }

  // iOS: Calendar.dateComponents([.year], from:to:).year —— 历法整年差。
  private static wholeYearsBetween(fromMs: number, toMs: number): number {
    const f = new Date(fromMs);
    const t = new Date(toMs);
    let years = t.getFullYear() - f.getFullYear();
    // 未满整年则减一（按月/日比较）。
    if (t.getMonth() < f.getMonth()
      || (t.getMonth() === f.getMonth() && t.getDate() < f.getDate())) {
      years -= 1;
    }
    return years;
  }
}

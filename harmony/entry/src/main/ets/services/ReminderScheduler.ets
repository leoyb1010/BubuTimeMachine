import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/AppDatabase';
import { AgeCalculator } from '../models/AgeCalculator';
import type { Entry, ChildProfile } from '../models/Models';

const DOMAIN = 0x0000;

// MARK: - 那年今日 · 提醒调度（对照 iOS Services/ReminderScheduler.swift）
// 每天上午 9:00 提醒一次：往年的今天，布布在做什么。
// 旧实现是「单条 repeats=true 通知」——文案在 App 打开那天算好后每天重复，
// 第二天起内容必然过期/错误。现改为预排未来 7 天，每天各自取对应日期的回忆；
// App 每次活跃时滚动刷新这 7 天。
//
// iOS 用 UserNotifications(UNUserNotificationCenter + UNCalendarNotificationTrigger)；
// HarmonyOS 用 @ohos.reminderAgentManager(reminderAgentManager) 发布日历型定时提醒（CALENDAR），
// 授权用 @kit.NotificationKit notificationManager.requestEnableNotification。
// iOS 用字符串 identifier 去重/撤销；HarmonyOS publishReminder 返回数字 reminderId，
// 我们把「offset(0..<7) → reminderId」的映射持久化在内存，刷新时先批量 cancel 旧的再重排。
export class ReminderScheduler {
  static readonly shared = new ReminderScheduler();

  // iOS: private let identifierPrefix / daysAhead
  private readonly daysAhead: number = 7;

  // offset → 已发布的 reminderId（对应 iOS 的 "bubu.onThisDay.<offset>" 标识集合）。
  private publishedReminderIds: number[] = [];

  private constructor() {}

  // iOS: func update(enabled:context:) async
  // 开关变化时调用。开 → 申请授权后重排未来 7 天；关 → 撤销全部待发提醒。
  async update(enabled: boolean): Promise<void> {
    if (enabled) {
      const granted = await this.requestAuthorization();
      if (!granted) return;
      await this.scheduleWeekAhead();
    } else {
      await this.cancelAll();
    }
  }

  // iOS: func refreshIfEnabled(enabled:context:)
  // App 启动时按开关状态刷新（滚动重排未来 7 天）。
  async refreshIfEnabled(enabled: boolean): Promise<void> {
    if (!enabled) return;
    await this.scheduleWeekAhead();
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
  private async scheduleWeekAhead(): Promise<void> {
    await this.cancelAll();

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
        notificationId: 9100 + offset,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };

      try {
        const id: number = await reminderAgentManager.publishReminder(reminder);
        this.publishedReminderIds.push(id);
      } catch (e) {
        hilog.error(DOMAIN, 'Bubu', `发布提醒失败 offset=${offset}: ${JSON.stringify(e)}`);
      }
    }
  }

  // iOS: center.removePendingNotificationRequests(withIdentifiers: ...)
  private async cancelAll(): Promise<void> {
    for (const id of this.publishedReminderIds) {
      try {
        await reminderAgentManager.cancelReminder(id);
      } catch (e) {
        // 已触发 / 已撤销：忽略。
      }
    }
    this.publishedReminderIds = [];
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

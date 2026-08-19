import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { WeeklyReport } from '../models/AIArtifacts';

// 新周报只发不含家庭正文的本地通知；发布成功后才记录去重 id。
export class WeeklyReportNotifier {
  static async notifyIfNew(context: common.UIAbilityContext, report: WeeklyReport): Promise<void> {
    if (report.status !== 'ready' || !(await notificationManager.isNotificationEnabled())) return;
    const store = await preferences.getPreferences(context, 'bubu_weekly_report_notice');
    if ((await store.get('latestId', '') as string) === report.id) return;
    const request: notificationManager.NotificationRequest = {
      id: WeeklyReportNotifier.notificationId(report.id),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '布布周报写好了',
          text: '这一周的小事已经整理好，每一段都附有原记录出处。'
        }
      },
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    };
    await notificationManager.publish(request);
    await store.put('latestId', report.id);
    await store.flush();
  }

  private static notificationId(id: string): number {
    let hash = 17;
    for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) & 0x7fffffff;
    return 9200 + hash % 100000;
  }
}

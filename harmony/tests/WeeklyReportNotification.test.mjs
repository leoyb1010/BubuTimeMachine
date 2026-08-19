import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const notifier = await readFile(new URL('../entry/src/main/ets/services/WeeklyReportNotifier.ets', import.meta.url), 'utf8');
const view = await readFile(new URL('../entry/src/main/ets/view/WeeklyReportView.ets', import.meta.url), 'utf8');

test('新周报使用不含家庭正文的本地通知，成功后按 report id 去重', () => {
  assert.ok(notifier.includes("report.status !== 'ready'"));
  assert.ok(notifier.includes('notificationManager.publish(request)'));
  assert.ok(notifier.includes("store.put('latestId', report.id)"));
  assert.ok(notifier.includes('这一周的小事已经整理好，每一段都附有原记录出处。'));
  assert.ok(view.includes('WeeklyReportNotifier.notifyIfNew'));
});

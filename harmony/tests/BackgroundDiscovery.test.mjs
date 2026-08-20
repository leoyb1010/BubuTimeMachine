import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const background = await readFile(new URL('../entry/src/main/ets/background/BackgroundSyncAbility.ets', import.meta.url), 'utf8');
const intake = await readFile(new URL('../entry/src/main/ets/services/PhotoIntakeService.ets', import.meta.url), 'utf8');
const notifier = await readFile(new URL('../entry/src/main/ets/services/WeeklyReportNotifier.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('WorkScheduler 在权限已授权时后台发现新照片且绝不后台弹权限框', () => {
  assert.ok(background.includes('PhotoIntakeService.shared.scanRecent(14, false)'));
  assert.ok(intake.includes('PermissionService.isGranted'));
  assert.ok(intake.includes('if (!requestPermission) return await this.cachedGroups()'));
});

test('新周报在未打开周报页时由前台恢复和后台任务主动检查并去重通知', () => {
  assert.ok(notifier.includes('static async checkLatest'));
  assert.ok(background.includes('WeeklyReportNotifier.checkLatest(this.context)'));
  assert.ok(ability.includes('WeeklyReportNotifier.checkLatest(this.context)'));
  assert.ok(notifier.includes("store.get('latestId'"));
});

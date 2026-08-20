import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');
const advanced = await readFile(new URL('../entry/src/main/ets/view/AdvancedSettingsView.ets', import.meta.url), 'utf8');
const settings = await readFile(new URL('../entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8');
const reminders = await readFile(new URL('../entry/src/main/ets/services/ReminderScheduler.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('照片画面搜索默认关闭，只有用户明确开启后才发送搜索词', () => {
  assert.ok(config.includes('semanticSearchEnabled: boolean = false'));
  assert.ok(advanced.includes("Text('搜索照片里的画面')"));
  assert.ok(timeline.includes('!ServerConfig.shared.semanticSearchEnabled'));
});

test('每日回忆开关持久化并在启动和回前台滚动重排', () => {
  assert.ok(config.includes('dailyReminderEnabled: boolean = false'));
  assert.ok(settings.includes("Text('那年今日 · 每日回忆')"));
  assert.ok(settings.includes('ServerConfig.shared.setDailyReminderEnabled(value)'));
  assert.ok(ability.includes('ReminderScheduler.shared.refreshIfEnabled(ServerConfig.shared.dailyReminderEnabled)'));
});

test('提醒跨进程去重并覆盖 30 天回忆与最近疫苗预告和到期日', () => {
  assert.ok(reminders.includes('private readonly daysAhead: number = 30'));
  assert.ok(reminders.includes('await reminderAgentManager.cancelAllReminders()'));
  assert.ok(reminders.includes('await this.scheduleVaccineReminders()'));
  assert.ok(reminders.includes('upcoming.slice(0, 3)'));
  assert.ok(reminders.includes("'疫苗预告 💉'"));
  assert.ok(reminders.includes("'今天该打疫苗啦 💉'"));
});

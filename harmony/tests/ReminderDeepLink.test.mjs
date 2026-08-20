import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const reminders = await readFile(new URL('../entry/src/main/ets/services/ReminderScheduler.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('每日回忆和疫苗提醒点击均通过 wantAgent 打开 EntryAbility 并携带预填草稿', () => {
  assert.ok(reminders.includes("pkgName: 'com.bubu.timemachine'"));
  assert.ok(reminders.includes("abilityName: 'EntryAbility'"));
  assert.ok(reminders.includes("'bubuReminderDraft': '今天的布布……'"));
  assert.ok(reminders.includes("parameters: { 'bubuReminderDraft': draft }"));
});

test('冷启动和已运行 onNewWant 都只预填确认页，不直接写数据库', () => {
  assert.ok(ability.includes('this.handleReminderWant(want)'));
  assert.ok(ability.includes('onNewWant('));
  assert.ok(ability.includes("AppStorage.setOrCreate('bubuIntentDraft'"));
  const method = ability.slice(ability.indexOf('private handleReminderWant'));
  assert.ok(!method.includes('AppDatabase.shared.insert'));
});

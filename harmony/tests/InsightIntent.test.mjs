import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../entry/src/main/ets/intent/OpenBubuIntent.ets', import.meta.url), 'utf8');
const record = await readFile(new URL('../entry/src/main/ets/intent/RecordMomentIntent.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');

test('鸿蒙系统意图可在前台打开布布时光机', () => {
  assert.ok(source.includes("intentName: 'BubuOpenApp'"));
  assert.ok(source.includes('UI_ABILITY_FOREGROUND'));
  assert.ok(source.includes("abilityName: 'EntryAbility'"));
});

test('带参数快捷记录用 JSON Schema 注入原话并停在用户确认页', () => {
  assert.ok(record.includes("intentName: 'BubuRecordMoment'"));
  assert.ok(record.includes("'$schema': 'http://json-schema.org/draft-07/schema#'"));
  assert.ok(record.includes("'required': ['note']"));
  assert.ok(record.includes("public note: string = ''"));
  assert.ok(record.includes("AppStorage.setOrCreate('bubuIntentDraft', value)"));
  assert.ok(home.includes('this.startQuickCapture(this.consumeIntentDraft())'));
});

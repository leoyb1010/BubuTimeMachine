import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const home = await readFile(new URL('view/HomeView.ets', root), 'utf8');
const studio = await readFile(new URL('view/AIStudioView.ets', root), 'utf8');
const settings = await readFile(new URL('view/SettingsView.ets', root), 'utf8');
const simple = await readFile(new URL('view/SimpleModeView.ets', root), 'utf8');

test('首页只保留高频任务，空库单焦点且今日一问不再占四宫格', () => {
  assert.ok(home.includes('this.firstRecordEmptyState()'));
  assert.ok(home.includes('this.dailyQuestionStrip()'));
  assert.ok(!home.includes('dashboardGridTop'));
  assert.ok(!home.includes('constellationTile'));
  assert.ok(!home.includes('growthTile'));
  assert.ok(!home.includes('storyTile'));
});

test('魔法屋使用一个主位和回顾创作声音分区，成长之声有真实入口', () => {
  assert.ok(studio.includes('this.askBubuCard()'));
  for (const title of ['回顾', '创作', '声音']) assert.ok(studio.includes(`sectionHeader('${title}'`));
  assert.ok(studio.includes("route: 'voiceArchive'"));
  assert.ok(studio.includes('VoiceArchiveView'));
});

test('设置只保留配置，健康和成长之声分别回到业务入口', () => {
  assert.ok(!settings.includes('showHealth'));
  assert.ok(!settings.includes('showVoiceArchive'));
  assert.ok(!settings.includes("navRow('健康记录'"));
  assert.ok(!settings.includes("navRow('成长之声'"));
  assert.ok(home.includes("quickDockButton(BubuIconName.health, '健康'"));
});

test('姥姥模式明确区分当前使用者和被记录的孩子', () => {
  assert.ok(simple.includes('当前身份：'));
  assert.ok(simple.includes("Text('记录的是')"));
  assert.ok(simple.includes('currentMember?.avatarEmoji'));
  assert.ok(simple.includes('childAvatarSrc()'));
  assert.ok(simple.includes('constraintSize({ minHeight: 118 })'));
  assert.ok(!simple.includes(".height(118)"));
});

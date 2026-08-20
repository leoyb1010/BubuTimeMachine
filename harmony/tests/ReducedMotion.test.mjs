import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const preference = await readFile(new URL('../entry/src/main/ets/theme/MotionPreference.ets', import.meta.url), 'utf8');
const motion = await readFile(new URL('../entry/src/main/ets/theme/BubuMotion.ets', import.meta.url), 'utf8');
const frame = await readFile(new URL('../entry/src/main/ets/view/PhotoFrameView.ets', import.meta.url), 'utf8');
const ceremony = await readFile(new URL('../entry/src/main/ets/components/CeremonyAnimation.ets', import.meta.url), 'utf8');

test('启动读取系统动画缩放并统一关闭循环和过渡动画', () => {
  assert.ok(preference.includes('ANIMATOR_DURATION_SCALE'));
  assert.ok(preference.includes('TRANSITION_ANIMATION_SCALE'));
  assert.ok(preference.includes("AppStorage.setOrCreate('bubuReduceMotion', reduced)"));
  assert.ok(motion.includes('BubuMotion.reduced ? 1 : -1'));
});

test('减少动态效果时相框 Ken Burns 和典礼星点停止', () => {
  assert.ok(frame.includes("@StorageLink('bubuReduceMotion')"));
  assert.ok(frame.includes('this.reduceMotion ? 0 : this.dwell * 1000'));
  assert.ok(ceremony.includes('this.reduceMotion || this.systemReduceMotion'));
  assert.ok(ceremony.includes('!this.systemReduceMotion'));
});

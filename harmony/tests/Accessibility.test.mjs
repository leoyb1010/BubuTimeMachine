import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const tab = await readFile(new URL('../entry/src/main/ets/components/BubuGlassTabBar.ets', import.meta.url), 'utf8');
const voice = await readFile(new URL('../entry/src/main/ets/components/VoiceComponents.ets', import.meta.url), 'utf8');
const media = await readFile(new URL('../entry/src/main/ets/components/MediaThumbnail.ets', import.meta.url), 'utf8');
const icon = await readFile(new URL('../entry/src/main/ets/components/BubuIcon.ets', import.meta.url), 'utf8');

test('核心图形控件向屏幕朗读暴露动作语义，装饰画布不重复朗读', () => {
  for (const label of ["accessibilityText(item.title)", "accessibilityText('记录此刻')"]) assert.ok(tab.includes(label));
  for (const label of ['停止并保存录音', '开始录音', '暂停语音', '播放语音']) assert.ok(voice.includes(label));
  for (const label of ['媒体正在下载', "return '视频'", "return '语音'", "return '照片'"]) assert.ok(media.includes(label));
  assert.ok(icon.includes("accessibilityLevel('no')"));
  assert.ok(voice.includes("accessibilityLevel('no')"));
});

import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const sound = await readFile(new URL('../entry/src/main/ets/theme/BubuSound.ets', import.meta.url), 'utf8');
const settings = await readFile(new URL('../entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8');
const capture = await readFile(new URL('../entry/src/main/ets/view/CaptureModel.ets', import.meta.url), 'utf8');
const ceremony = await readFile(new URL('../entry/src/main/ets/components/CeremonyAnimation.ets', import.meta.url), 'utf8');
const compose = await readFile(new URL('../entry/src/main/ets/view/CapsuleComposeView.ets', import.meta.url), 'utf8');
const unlock = await readFile(new URL('../entry/src/main/ets/view/CapsuleUnlockView.ets', import.meta.url), 'utf8');

test('五个本地短音资源存在并通过 raw fd 播放且默认关闭可持久化', async () => {
  for (const name of ['save', 'seal', 'unlock', 'milestone', 'birthday']) {
    await access(new URL(`../entry/src/main/resources/rawfile/sfx-${name}.caf`, import.meta.url));
  }
  assert.ok(sound.includes('getRawFdSync'));
  assert.ok(sound.includes('closeRawFdSync'));
  assert.ok(sound.includes('private static enabled: boolean = false'));
  assert.ok(settings.includes("Text('温柔提示音')"));
});

test('保存、里程碑、胶囊封存与解锁触发对应提示音', () => {
  assert.ok(capture.includes('BubuSound.play(SoundEffect.save)'));
  assert.ok(ceremony.includes('BubuSound.play(SoundEffect.milestone)'));
  assert.ok(compose.includes('BubuSound.play(SoundEffect.seal)'));
  assert.ok(unlock.includes('BubuSound.play(SoundEffect.unlock)'));
});

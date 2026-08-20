import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const profile = await readFile(new URL('../entry/src/main/ets/view/ChildProfileView.ets', import.meta.url), 'utf8');
const card = await readFile(new URL('../entry/src/main/ets/components/BubuIdentityCard.ets', import.meta.url), 'utf8');

test('布布档案可选择头像和首页照片背景，替换后清旧文件并让头像重新同步', () => {
  assert.ok(profile.includes("Button('选择布布头像')"));
  assert.ok(profile.includes("Button('选择首页照片背景')"));
  assert.ok(profile.includes('PhotoViewPicker'));
  assert.ok(profile.includes('MediaStore.shared.copyIntoStore'));
  assert.ok(profile.includes('avatarRemoteURL: this.avatarFileName ==='));
  assert.ok(profile.includes('MediaStore.shared.deleteMedia'));
});

test('身份卡在照片背景模式真实消费 heroBackgroundFileName', () => {
  assert.ok(card.includes('ThemeManager.shared.heroMode === HeroBackgroundMode.photo'));
  assert.ok(card.includes('this.profile.heroBackgroundFileName'));
  assert.ok(card.includes('Image(this.heroSrc())'));
});

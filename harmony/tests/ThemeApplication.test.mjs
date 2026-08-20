import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const theme = await readFile(new URL('../entry/src/main/ets/theme/ThemeManager.ets', import.meta.url), 'utf8');
const colors = await readFile(new URL('../entry/src/main/ets/theme/BubuTheme.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');
const card = await readFile(new URL('../entry/src/main/ets/components/BubuIdentityCard.ets', import.meta.url), 'utf8');

test('选择八套主题会更新全局语义主色，不再只改 Tab 和图标', () => {
  assert.ok(colors.includes('static setThemePrimary'));
  assert.ok(colors.includes('return BubuColor.themePrimary'));
  assert.ok(theme.includes('BubuColor.setThemePrimary(this.semanticPrimary())'));
  for (const id of ['sky', 'mint', 'lavender', 'peach', 'night', 'cream', 'dusk']) {
    assert.ok(theme.includes(`case '${id}'`));
  }
});

test('深色核心页不再使用硬编码浅色背景，照片背景模式被首页身份卡消费', () => {
  for (const source of [home, card]) {
    assert.ok(!source.includes("backgroundColor('#F2FFFFFF')"));
    assert.ok(!source.includes("backgroundColor('#F3F3F3')"));
  }
  assert.ok(card.includes('HeroBackgroundMode.photo'));
  assert.ok(card.includes('Image(this.heroSrc())'));
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const app = await readFile(new URL('../AppScope/app.json5', import.meta.url), 'utf8');
const icon = await readFile(new URL('../entry/src/main/ets/theme/AppIconManager.ets', import.meta.url), 'utf8');
const theme = await readFile(new URL('../entry/src/main/ets/theme/ThemeManager.ets', import.meta.url), 'utf8');

test('API 26 主题图标声明完整并调用系统 alternate icon', () => {
  for (const name of ['sky', 'mint', 'lavender', 'peach', 'night', 'cream', 'birthday']) {
    assert.ok(app.includes(`AppIcon-${name}`));
  }
  assert.ok(icon.includes('bundleManager.setAlternateIcon'));
  assert.ok(icon.includes("case 'dusk': return 'AppIcon-peach'"));
  assert.ok(theme.includes('AppIconManager.apply(theme.id, this.birthdayMonth)'));
  assert.ok(theme.includes('setBirthdayMonth(enabled: boolean)'));
});

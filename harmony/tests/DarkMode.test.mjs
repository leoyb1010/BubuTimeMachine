import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const colors = await readFile(new URL('../entry/src/main/ets/theme/BubuTheme.ets', import.meta.url), 'utf8');
const manager = await readFile(new URL('../entry/src/main/ets/theme/ThemeManager.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('星夜和系统深色统一切换全局语义色而不是只换背景', () => {
  for (const token of ['warmBrown', 'cream', 'card', 'secondaryText', 'background', 'softFill', 'hairline']) {
    assert.ok(colors.includes(`static get ${token}`), `${token} 应为运行时语义色`);
  }
  assert.ok(manager.includes('BubuColor.setDarkMode(forceDark || this.systemDark)'));
  assert.ok(manager.includes('context.setColorMode'));
  assert.ok(manager.includes('COLOR_MODE_NOT_SET'));
  assert.ok(ability.includes('onConfigurationUpdate'));
  assert.ok(ability.includes('updateSystemColorMode(newConfig.colorMode)'));
});

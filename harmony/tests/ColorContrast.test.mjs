import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const theme = await readFile(new URL('../entry/src/main/ets/theme/BubuTheme.ets', import.meta.url), 'utf8');

function luminance(hex) {
  const values = hex.match(/[0-9A-Fa-f]{2}/g).map((part) => parseInt(part, 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2];
}

function contrast(a, b) {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

test('语义按钮和状态色承载白字均达到 WCAG AA 4.5:1', () => {
  for (const color of ['B23A58', '43734D', '9A5B00', '3B69A4', '9F2F54']) {
    assert.ok(contrast(color, 'FFFFFF') >= 4.5, color);
    assert.ok(theme.toUpperCase().includes(`#${color}`));
  }
});

test('浅色模式次级小字对白底达到 WCAG AA 4.5:1', () => {
  assert.ok(contrast('6E5A52', 'FFFFFF') >= 4.5);
  assert.ok(theme.includes("'#6E5A52'"));
  assert.ok(theme.includes("static readonly pink   = '#FFC2D6'"), '装饰浅粉应保留，不承担正文可读性');
});

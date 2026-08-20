import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ceremony = await readFile(new URL('../entry/src/main/ets/components/CeremonyAnimation.ets', import.meta.url), 'utf8');

test('里程碑典礼使用正式布布吉祥物资产，不再用 emoji 占位', () => {
  assert.ok(ceremony.includes('BubuMascotBadge'));
  assert.ok(ceremony.includes('BubuExpression.cheer'));
  assert.ok(!ceremony.includes("Text('🎉')"));
  assert.ok(!ceremony.includes('emoji 占位'));
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { parseNaturalCaptureOfflineWire } from '../entry/src/main/ets/services/OnDeviceNaturalParser.ts';

test('离线自然记录只保存原文，不编造数值或健康类别', () => {
  const result = parseNaturalCaptureOfflineWire({
    text: '布布今天好像喝了不少水', childName: '布布', timezone: 'Asia/Shanghai',
    referenceDate: '2026-08-19T08:00:00.000Z'
  });
  assert.equal(result.items[0].domain, 'timeline');
  assert.equal(result.items[0].note, '布布今天好像喝了不少水');
  assert.deepEqual(result.items[0].fields, {});
  assert.deepEqual(result.warnings, ['offline_plain_text']);
});

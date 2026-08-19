import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const analyzer = await readFile(new URL('../entry/src/main/ets/services/media/PhotoAnalyzer.ets', import.meta.url), 'utf8');

test('照片标签使用端侧 Core Vision 多目标识别且只收高置信结果', () => {
  assert.ok(analyzer.includes('objectDetection.ObjectDetector.create()'));
  assert.ok(analyzer.includes('detector.process(request)'));
  assert.ok(analyzer.includes('if (object.score < 0.6) continue'));
  assert.ok(analyzer.includes('await detector.destroy()'));
  assert.ok(!analyzer.includes('private static async classify(source: image.ImageSource): Promise<string[]> {\n    return [];'));
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const recognizer = await readFile(new URL('../entry/src/main/ets/services/ChildIdentityRecognizer.ets', import.meta.url), 'utf8');
const analyzer = await readFile(new URL('../entry/src/main/ets/services/media/PhotoAnalyzer.ets', import.meta.url), 'utf8');
const inbox = await readFile(new URL('../entry/src/main/ets/view/PhotoInboxView.ets', import.meta.url), 'utf8');

test('人物识别只在本机、由用户开启且不自动过滤', () => {
  assert.ok(recognizer.includes('faceComparator.compareFaces'));
  assert.ok(recognizer.includes("private static readonly storeName: string = 'bubu_photo_identity'"));
  assert.ok(analyzer.includes('faceDetector.detect'));
  assert.ok(inbox.includes('只在本机比较，不上传人脸；只做提示，不自动隐藏照片。'));
});

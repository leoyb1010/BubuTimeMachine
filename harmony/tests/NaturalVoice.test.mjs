import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const view = await readFile(new URL('../entry/src/main/ets/view/NaturalCaptureBar.ets', import.meta.url), 'utf8');
const service = await readFile(new URL('../entry/src/main/ets/services/AIService.ets', import.meta.url), 'utf8');

test('一句话记录支持真实录音转写、失败重试和成功清理临时音频', () => {
  assert.ok(view.includes('AudioRecorder.shared'));
  assert.ok(view.includes('AIService.shared.transcribe'));
  assert.ok(view.includes("Text('重试转写')"));
  assert.ok(view.includes('MediaStore.shared.deleteMedia(fileName)'));
  assert.ok(view.includes('await this.parseText()'));
  assert.ok(service.includes("this.baseURL + '/transcribe'"));
  assert.ok(service.includes('multiFormDataList'));
});

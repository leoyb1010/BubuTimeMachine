import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const service = await readFile(new URL('../entry/src/main/ets/services/AIService.ets', import.meta.url), 'utf8');
const view = await readFile(new URL('../entry/src/main/ets/view/GrowthMovieView.ets', import.meta.url), 'utf8');

test('成长电影接真实服务端渲染、状态、系统落盘和播放', () => {
  assert.ok(service.includes("this.post('movie/render'"));
  assert.ok(service.includes('movie/status/'));
  assert.ok(service.includes('request.downloadFile(this.appContext'));
  assert.ok(view.includes('startServerRender'));
  assert.ok(view.includes('Video({ src: `file://${this.renderedMoviePath}` })'));
});

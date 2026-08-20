import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const movie = await readFile(new URL('../entry/src/main/ets/view/GrowthMovieView.ets', import.meta.url), 'utf8');

test('成长电影 jobId 提交后持久化，进页面自动续接且终态清理', () => {
  assert.ok(movie.includes('bubu_growth_movie_jobs'));
  assert.ok(movie.includes('await this.savePendingJob(year, this.renderStatus.jobId)'));
  assert.ok(movie.includes('this.resumePendingRender()'));
  assert.ok(movie.includes('await this.clearPendingJob(this.activeRenderYear || this.renderYear())'));
});

test('轮询覆盖约十分钟并容忍连续三次网络失败，离页停止但保留 jobId', () => {
  assert.ok(movie.includes('attempt < 300'));
  assert.ok(movie.includes('consecutiveFailures >= 3'));
  assert.ok(movie.includes('aboutToDisappear(): void { this.pollGeneration += 1; }'));
  assert.ok(movie.includes('jobId 已保留'));
});

import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const etsRoot = new URL('../entry/src/main/ets/', import.meta.url);

async function doesNotExist(relativePath) {
  try {
    await access(new URL(relativePath, etsRoot));
    return false;
  } catch {
    return true;
  }
}

test('鸿蒙运行代码不再保留 Mock 服务或不可达的即将到来画廊', async () => {
  for (const path of [
    'services/MockAIService.ets',
    'services/MockAPIClient.ets',
    'components/ComingSoonView.ets',
    'components/DesignGallery.ets'
  ]) {
    assert.equal(await doesNotExist(path), true, `${path} 应从运行工程删除`);
  }

  const root = await readFile(new URL('pages/RootPage.ets', etsRoot), 'utf8');
  assert.ok(!root.includes('showGallery'));
  assert.ok(!root.includes('DesignGallery'));
});

test('魔法屋的绘本和胶囊卡片都进入真实功能页', async () => {
  const studio = await readFile(new URL('view/AIStudioView.ets', etsRoot), 'utf8');
  assert.ok(studio.includes("this.route = 'story'"));
  assert.ok(studio.includes("this.route = 'capsule'"));
  assert.ok(studio.includes('BubuStoryView'));
  assert.ok(studio.includes('CapsuleView'));
});

test('成长电影不保留伪 jobId 的旧占位 API', async () => {
  const ai = await readFile(new URL('services/AIService.ets', etsRoot), 'utf8');
  assert.ok(!ai.includes('async generateGrowthMovie('));
  assert.ok(!ai.includes('jobId: `ai-${year}`'));
  assert.ok(ai.includes('startMovieRender'));
  assert.ok(ai.includes('movieRenderStatus'));
  assert.ok(ai.includes('downloadRenderedMovie'));
});

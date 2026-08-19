import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const view = await readFile(new URL('../entry/src/main/ets/view/FamilyEnsembleView.ets', import.meta.url), 'utf8');

test('家人合奏过滤反应哨兵、优先真实 AI、失败才明示本机模板', () => {
  assert.ok(view.includes('!ReactionUtil.isReaction(comment)'));
  assert.ok(view.includes('AIService.shared.rewriteFirstPerson'));
  assert.ok(view.includes('不要添加原文没有的事实'));
  assert.ok(view.includes('本机简易合奏'));
  assert.ok(view.includes('token !== this.generationToken'));
  assert.ok(!view.includes('// Mock 合成'));
});

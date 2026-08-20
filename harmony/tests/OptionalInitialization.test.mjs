import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('可选服务按依赖阶段独立降级，单项失败不会跳过后续任务', () => {
  assert.ok(ability.includes('private async runOptional'));
  for (const name of ['界面偏好', '胶囊密文自检', '媒体与照片收件箱', '服务器配置',
    '本地数据归一化', '同步引擎', '系统提醒', '周报通知', '后台任务']) {
    assert.ok(ability.includes(`runOptional('${name}'`), name);
  }
  assert.ok(ability.includes('其他能力继续'));
});

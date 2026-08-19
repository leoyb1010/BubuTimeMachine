import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const refresher = await readFile(new URL('../entry/src/main/ets/theme/WidgetRefresher.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/widget/BubuFormAbility.ets', import.meta.url), 'utf8');
const card = await readFile(new URL('../entry/src/main/ets/widget/pages/BubuCard.ets', import.meta.url), 'utf8');

test('服务卡片持久注册 formId 并展示真实成长快照', () => {
  assert.ok(refresher.includes("private static readonly formStore: string = 'bubu_widget_forms'"));
  assert.ok(refresher.includes("store.putSync('formIds'"));
  assert.ok(ability.includes('WidgetRefresher.register(this.context, formId)'));
  assert.ok(ability.includes('WidgetRefresher.unregister(this.context, formId)'));
  for (const field of ['recentTitle', 'statsText', 'growthText', 'nextMilestone', 'recentPhotoUri']) {
    assert.ok(card.includes(`@LocalStorageProp('${field}')`));
  }
  assert.ok(refresher.includes("store.putSync('recentPhotoUri'"));
  assert.ok(card.includes('Image(this.recentPhotoUri)'));
  assert.ok(card.includes("'action': 'router'"));
});

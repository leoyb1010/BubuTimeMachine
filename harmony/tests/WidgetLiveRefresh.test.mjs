import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const widget = await readFile(new URL('../entry/src/main/ets/theme/WidgetRefresher.ets', import.meta.url), 'utf8');
const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');

test('所有本地 RDB 写入通过数据变更观察器防抖刷新服务卡片', () => {
  assert.ok(db.includes('SUBSCRIBE_TYPE_LOCAL_DETAILS'));
  assert.ok(db.includes('if (this.dataChangeListener) this.dataChangeListener()'));
  assert.ok(ability.includes('AppDatabase.shared.setDataChangeListener'));
  assert.ok(widget.includes('static requestRefresh()'));
  assert.ok(widget.includes('WidgetRefresher.reload(context)'));
});

test('服务卡片使用未归档记录中最近的实际照片并持久化缩略图', () => {
  assert.ok(widget.includes('activeEntryIds.has(item.entryId)'));
  assert.ok(widget.includes("item.resourceRoleRaw === 'display'"));
  assert.ok(widget.includes('entries.map((entry) => photos.find'));
  assert.ok(widget.includes('MediaDerivationService.prepare(recentPhoto)'));
  assert.ok(widget.includes('AppDatabase.shared.updateMediaDerivedFields(recentPhoto.id'));
  assert.ok(!widget.includes('MediaStore.shared.fullPath(photo.localFileName)'));
});

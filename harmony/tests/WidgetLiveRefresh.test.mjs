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

test('服务卡片照片只统计未归档记录且缩略图缺失时回退原图', () => {
  assert.ok(widget.includes('activeEntryIds.has(item.entryId)'));
  assert.ok(widget.includes("item.resourceRoleRaw === 'display'"));
  assert.ok(widget.includes('MediaStore.shared.thumbnailExists(photo.thumbnailFileName)'));
  assert.ok(widget.includes('MediaStore.shared.exists(photo.localFileName)'));
});

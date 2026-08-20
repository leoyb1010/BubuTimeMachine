import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const view = await readFile(new URL('../entry/src/main/ets/view/SyncCenterView.ets', import.meta.url), 'utf8');
const frame = await readFile(new URL('../entry/src/main/ets/view/PhotoFrameView.ets', import.meta.url), 'utf8');

test('本机全量重传只标记待同步并走正常 LWW，不清空或强盖远端', () => {
  assert.ok(db.includes('async markAllServerBackedDataDirty'));
  const method = db.slice(db.indexOf('async markAllServerBackedDataDirty'));
  assert.ok(!method.slice(0, method.indexOf('\n  }')).includes('delete('));
  assert.ok(sync.includes('await AppDatabase.shared.markAllServerBackedDataDirty()'));
  assert.ok(sync.includes('await this.syncNow(true)'));
  assert.ok(view.includes("title: '重新上传本机全部内容？'"));
  assert.ok(view.includes('远端更新版本仍优先保留'));
});

test('相框一次批量查询媒体且只展示 display 资源，缩略图缺失回退原图', () => {
  assert.ok(frame.includes('AppDatabase.shared.fetchMediaForEntries'));
  assert.ok(!frame.includes('await AppDatabase.shared.fetchMediaForEntry(entry.id)'));
  assert.ok(frame.includes("item.resourceRoleRaw === 'display'"));
  assert.ok(frame.includes('MediaStore.shared.thumbnailExists'));
});

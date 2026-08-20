import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const db = await readFile(new URL('data/AppDatabase.ets', root), 'utf8');
const home = await readFile(new URL('view/HomeView.ets', root), 'utf8');
const timeline = await readFile(new URL('view/TimelineView.ets', root), 'utf8');

test('首页和时光轴批量读取封面媒体，不再按每条记录执行一次 SQL', () => {
  assert.ok(db.includes('async fetchMediaForEntries(entryIds: string[])'));
  assert.ok(db.includes("pred.in('entryId', entryIds)"));
  assert.ok(timeline.includes('AppDatabase.shared.fetchMediaForEntries'));
  const loader = timeline.slice(timeline.indexOf('private async loadPhotoMap'), timeline.indexOf('// MARK: 分段'));
  assert.ok(!loader.includes('fetchMediaForEntry('));
  const homeReload = home.slice(home.indexOf('private async reload'), home.indexOf('private async refreshSSDIntake'));
  assert.ok(!homeReload.includes('fetchMediaForEntry('));
  assert.ok(homeReload.includes('orderedPhotos'));
});

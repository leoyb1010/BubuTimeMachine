import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const rootPage = await readFile(new URL('pages/RootPage.ets', root), 'utf8');
const home = await readFile(new URL('view/HomeView.ets', root), 'utf8');
const timeline = await readFile(new URL('view/TimelineView.ets', root), 'utf8');
const studio = await readFile(new URL('view/AIStudioView.ets', root), 'utf8');
const milestones = await readFile(new URL('view/MilestonesView.ets', root), 'utf8');
const settings = await readFile(new URL('view/SettingsView.ets', root), 'utf8');
const detail = await readFile(new URL('view/EntryDetailView.ets', root), 'utf8');
const album = await readFile(new URL('view/AlbumView.ets', root), 'utf8');
const albumDetail = await readFile(new URL('view/AlbumDetailView.ets', root), 'utf8');

test('Root 每次先交给唯一最深层处理器，不再广播给多个页面', () => {
  assert.ok(rootPage.includes('BackDispatcher.shared.handleBack()'));
  assert.ok(!rootPage.includes('bubuBackSignal'));
  assert.ok(!rootPage.includes('bubuNavigationDepth'));
  const back = rootPage.slice(rootPage.indexOf('onBackPress()'), rootPage.indexOf('build()', rootPage.indexOf('onBackPress()')));
  assert.ok(back.includes('return false'));
  assert.ok(!back.includes('this.selection = 0'));
});

test('各主 Tab、设置、相册与详情弹层注册并在销毁时注销返回处理器', () => {
  for (const source of [home, timeline, studio, milestones, settings, detail, album, albumDetail]) {
    assert.ok(source.includes('BackDispatcher.shared.register'));
    assert.ok(source.includes('BackDispatcher.shared.unregister'));
    assert.ok(source.includes('syncBackHandler'));
  }
  assert.ok(detail.includes('this.viewingMediaID = null'));
  assert.ok(album.includes("register('album', 20"));
  assert.ok(albumDetail.includes("register('album-detail', 30"));
  assert.ok(timeline.includes("register('timeline', 20"));
  assert.ok(home.includes("register('home', 10"));
});

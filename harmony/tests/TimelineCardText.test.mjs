import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');

test('无标题时正文只作为卡片标题显示一次，标题与正文相同也不重复', () => {
  assert.ok(timeline.includes('private cardSubtitle(entry: Entry)'));
  assert.ok(timeline.includes('title.length === 0'));
  assert.ok(timeline.includes('note === title'));
  assert.ok(timeline.includes('if (this.cardSubtitle(entry) !== undefined)'));
});

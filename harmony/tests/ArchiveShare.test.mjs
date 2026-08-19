import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const exporter = await readFile(new URL('../entry/src/main/ets/services/media/ArchiveExporter.ets', import.meta.url), 'utf8');
const share = await readFile(new URL('../entry/src/main/ets/services/ShareService.ets', import.meta.url), 'utf8');

test('开放档案先压缩为 zip 再交给系统分享', () => {
  assert.ok(exporter.includes('zlib.compressFile(folder, zipPath'));
  assert.ok(share.includes("utd: 'general.zip-archive'"));
  assert.ok(share.includes('new systemShare.ShareController'));
  assert.ok(share.includes('fileUri.getUriFromPath(path)'));
});

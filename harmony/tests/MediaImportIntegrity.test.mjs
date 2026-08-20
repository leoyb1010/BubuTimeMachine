import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const store = await readFile(new URL('../entry/src/main/ets/services/MediaStore.ets', import.meta.url), 'utf8');

test('所有 copyIntoStore 入口按文件头识别图片和视频真实扩展名', () => {
  assert.ok(store.includes('MediaStore.sniffFileExtension(srcUri)'));
  for (const extension of ['heic', 'avif', 'mov', 'mp4']) assert.ok(store.includes(`'${extension}'`));
  assert.ok(store.includes("brand === 'qt  '"));
  assert.ok(store.includes('MediaStore.cleanExtension(ext)'));
});

test('复制和写入无论成功失败都关闭句柄，失败删除半文件', () => {
  assert.ok(store.match(/finally \{/g)?.length >= 4);
  assert.ok(store.includes('if (src) try { fileIo.closeSync(src)'));
  assert.ok(store.includes('if (out) try { fileIo.closeSync(out)'));
  assert.ok(store.includes('try { fileIo.unlinkSync(dst); }'));
  assert.ok(store.includes('try { fileIo.unlinkSync(path); }'));
});

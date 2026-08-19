import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const exporter = await readFile(new URL('../entry/src/main/ets/services/media/ArchiveExporter.ets', import.meta.url), 'utf8');
const share = await readFile(new URL('../entry/src/main/ets/services/ShareService.ets', import.meta.url), 'utf8');

test('开放档案先压缩为 zip 再交给系统分享', () => {
  assert.ok(exporter.includes('zlib.compressFile(folder, zipPath'));
  assert.ok(share.includes("'general.zip-archive'"));
  assert.ok(share.includes('new systemShare.ShareController'));
  assert.ok(share.includes('fileUri.getUriFromPath(path)'));
});

test('年册由 PDF Kit 合成真实 PDF 并交给系统分享', async () => {
  const yearbook = await readFile(new URL('../entry/src/main/ets/services/media/YearbookExporter.ets', import.meta.url), 'utf8');
  const view = await readFile(new URL('../entry/src/main/ets/view/YearbookView.ets', import.meta.url), 'utf8');
  assert.ok(yearbook.includes("import { pdfService } from '@kit.PDFKit'"));
  assert.ok(yearbook.includes('document.createDocument(PAGE_W, PAGE_H)'));
  assert.ok(yearbook.includes('document.insertBlankPage(index, PAGE_W, PAGE_H)'));
  assert.ok(yearbook.includes('addImageObject'));
  assert.ok(yearbook.includes('document.saveDocument(pdfPath)'));
  assert.ok(share.includes("'com.adobe.pdf'"));
  assert.ok(view.includes('ShareService.sharePDF'));
});

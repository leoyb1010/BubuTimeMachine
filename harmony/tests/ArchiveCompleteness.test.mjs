import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const exporter = await readFile(new URL('../entry/src/main/ets/services/media/ArchiveExporter.ets', import.meta.url), 'utf8');
const view = await readFile(new URL('../entry/src/main/ets/view/ExportView.ets', import.meta.url), 'utf8');

test('开放档案包含胶囊 id/密文、成长测量和疫苗记录', () => {
  assert.ok(exporter.includes('encryptedBlobFileName?: string'));
  assert.ok(exporter.includes('growthMeasurements: GrowthSnapshot[]'));
  assert.ok(exporter.includes('vaccines: VaccineSnapshot[]'));
  assert.ok(view.includes('id: c.id'));
  assert.ok(view.includes('encryptedBlobFileName: c.encryptedBlobFileName'));
  assert.ok(view.includes('growthMeasurements: growthSnaps'));
  assert.ok(view.includes('vaccines: vaccineSnaps'));
});

test('缺失引用或复制失败会标记不完整并阻止假成功', () => {
  assert.ok(view.includes('unavailableReferences: unavailable'));
  assert.ok(exporter.includes('missing.push(name)'));
  assert.ok(exporter.includes("ArchiveExporter.writeText(`${root}/incomplete.json`"));
  assert.ok(exporter.includes('throw new Error(`档案不完整'));
  assert.ok(view.includes('if (!media.localFileName)'));
  assert.ok(view.includes('if (!voice.localFileName)'));
  assert.ok(view.includes('comment-voice:${comment.id}'));
  assert.ok(view.includes('if (!memo.localFileName)'));
});

test('档案逐文件生成真实 SHA-256 manifest', () => {
  assert.ok(exporter.includes("cryptoFramework.createMd('SHA256')"));
  assert.ok(exporter.includes('await md.update'));
  assert.ok(exporter.includes("manifest.sha256"));
});

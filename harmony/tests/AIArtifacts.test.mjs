import assert from 'node:assert/strict';
import test from 'node:test';
import {
  decodeQAAnswer,
  decodeSemanticSearch,
  decodeWeeklyReport
} from '../entry/src/main/ets/models/AIArtifacts.ts';

test('AI 问答只保留服务端真实引用 id', () => {
  assert.deepEqual(decodeQAAnswer({ answer: '会走路了', used_ids: ['entry-1', 7] }), {
    answer: '会走路了', usedIds: ['entry-1']
  });
});

test('语义搜索解码保留本地 Entry 追溯关系', () => {
  const decoded = decodeSemanticSearch({
    query: '秋千', model_version: 'mobileclip-v1',
    hits: [{ asset_id: 'a', entry_local_id: 'entry-1', media_record_id: 'm', captured_at: '2026-08-01', score: 0.82, reason: '画面匹配' }]
  });
  assert.equal(decoded.hits[0].entryLocalId, 'entry-1');
  assert.equal(decoded.hits[0].score, 0.82);
});

test('周报段落和出处按服务端字段解码', () => {
  const report = decodeWeeklyReport({
    id: 'r1', artifact_key: 'weekly:r1', status: 'ready', title: '这一周', summary: '摘要',
    week_start: '2026-08-10', week_end: '2026-08-16', generated_at: '2026-08-17',
    model_version: 'v1', content_hash: 'hash',
    sections: [{ kind: 'growth', title: '成长', text: '长高了', sourceIds: ['s1'] }],
    source_refs: [{ source_id: 's1', collection: 'entries', record_id: 'remote', local_id: 'local', happened_at: '2026-08-12', title: '公园', excerpt: '荡秋千', kind: 'entry' }]
  });
  assert.equal(report.sections[0].sourceIds[0], 's1');
  assert.equal(report.sourceRefs[0].localId, 'local');
});

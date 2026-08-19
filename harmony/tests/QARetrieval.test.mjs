import assert from 'node:assert/strict';
import test from 'node:test';
import { retrieveQAContexts } from '../entry/src/main/ets/models/QARetrieval.ts';

const now = Date.parse('2026-08-19T12:00:00Z');
const facts = [
  { id: 'walk', happenedAt: now - 20 * 86400000, dateText: '最近', ageText: '2岁', text: '第一次自己走路' },
  { id: 'swing', happenedAt: Date.parse('2025-08-19T12:00:00Z'), dateText: '去年', ageText: '1岁', text: '在公园荡秋千' },
  { id: 'old', happenedAt: now - 300 * 86400000, dateText: '以前', ageText: '1岁', text: '普通记录' }
];

test('问答关键词优先命中真实记录', () => {
  assert.equal(retrieveQAContexts('什么时候会走路？', facts, now)[0].id, 'walk');
});

test('去年今天先按日期窗口检索', () => {
  assert.equal(retrieveQAContexts('去年今天在干嘛？', facts, now)[0].id, 'swing');
});

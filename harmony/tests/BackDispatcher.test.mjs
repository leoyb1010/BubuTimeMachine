import assert from 'node:assert/strict';
import test from 'node:test';
import { BackDispatcher } from '../entry/src/main/ets/services/BackDispatcher.ts';

test('一次返回只由优先级最高且最后注册的最深层处理器消费', () => {
  const dispatcher = new BackDispatcher();
  const calls = [];
  dispatcher.register('home', 10, () => { calls.push('home'); return true; });
  dispatcher.register('timeline', 20, () => { calls.push('timeline'); return true; });
  dispatcher.register('viewer', 30, () => { calls.push('viewer'); return true; });
  assert.equal(dispatcher.handleBack(), true);
  assert.deepEqual(calls, ['viewer']);
});

test('失效处理器返回 false 后自动移除并继续交给下一层', () => {
  const dispatcher = new BackDispatcher();
  const calls = [];
  dispatcher.register('parent', 10, () => { calls.push('parent'); return true; });
  dispatcher.register('stale', 20, () => { calls.push('stale'); return false; });
  assert.equal(dispatcher.handleBack(), true);
  assert.deepEqual(calls, ['stale', 'parent']);
});

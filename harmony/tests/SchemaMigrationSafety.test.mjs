import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');

test('迁移先用 PRAGMA 判列存在，ALTER 任何真实错误必须上抛', () => {
  assert.ok(db.includes('PRAGMA table_info(${table})'));
  const addStart = db.indexOf('private async addColumnIfMissing');
  const addEnd = db.indexOf('private async hasColumn', addStart);
  const add = db.slice(addStart, addEnd);
  assert.ok(add.includes('if (await this.hasColumn(table, column, transaction)) return'));
  assert.ok(add.includes('await transaction.execute(`ALTER TABLE'));
  assert.ok(add.includes('throw error as Error'), '记录诊断后仍必须上抛，不能吞掉 ALTER 失败');
});

test('整批 schema 迁移原子提交且提交前断言关键列', () => {
  assert.ok(db.includes('store.createTransaction()'));
  assert.ok(db.includes('transaction.querySql(`PRAGMA table_info'));
  assert.ok(db.includes('await this.assertRequiredColumns(transaction)'));
  assert.ok(db.includes('transaction.commit()'));
  assert.ok(db.includes('transaction.rollback()'));
  assert.ok(db.includes('数据库结构不完整'));
});

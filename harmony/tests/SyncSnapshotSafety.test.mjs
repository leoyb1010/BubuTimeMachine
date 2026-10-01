import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import vm from 'node:vm';
import { laterServerTimestamp } from '../entry/src/main/ets/sync/SyncCursor.ts';

// Execute production ArkTS method bodies. Only Harmony SDK I/O is substituted;
// conditional writes run against a real, disposable in-memory SQLite database.
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
function method(source, start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Missing production method: ${start}`);
  return source.slice(first, last);
}
const engineMethods = [
  method(sync, '  private async pushEntries(', '  // —— ChildProfile'),
  method(sync, '  private async pullCollection(', '  private async isPendingDeletion('),
  method(sync, '  private static applyEntry(', '  private async findEntry(')
].join('\n');
const databaseMethod = method(database, '  async updateEntryFieldsIfUnchanged(', '  async deleteEntryHard(');

function harness() {
  const context = vm.createContext({
    Date, Map, Set, Error, Promise, Object, laterServerTimestamp,
    DOMAIN: 0, hilog: { warn() {} },
    SyncState: { local: 'local', synced: 'synced', failed: 'failed', uploading: 'uploading' }
  });
  vm.runInContext(stripTypeScriptTypes(`
    class SyncEngine { ${engineMethods} }
    class AppDatabase { ${databaseMethod} }
    globalThis.Engine = SyncEngine; globalThis.Database = AppDatabase;
  `), context);
  const Engine = context.Engine;
  Engine.isDirty = state => state !== 'synced';
  Engine.isMissingOptionalCollectionError = () => false;
  Engine.errorText = error => error.message;
  Engine.rStr = (row, key) => typeof row[key] === 'string' ? row[key] : undefined;
  Engine.rNum = (row, key) => typeof row[key] === 'number' ? row[key] : undefined;
  Engine.rBool = (row, key) => row[key] === true;
  Engine.rDate = (row, key, fallback) => row[key] ? Date.parse(row[key]) : fallback;
  return { context, engine: new Engine(), database: new context.Database() };
}

function cursorHarness(records, tombstones = []) {
  const { context, engine } = harness();
  let checkpoint = '2026-08-01T00:00:00.000Z';
  context.APIClient = { shared: {
    fetchRecords: async () => records,
    fetchDeletedTombstones: async () => tombstones
  } };
  engine.getCursor = async () => checkpoint;
  engine.setCursor = async (_, next) => { checkpoint = next; };
  engine.removeRemoteTombstones = async () => {};
  return { context, engine, checkpoint: () => checkpoint };
}
const oldMedia = { id: 'old-media', updated: '2026-09-01T00:00:00.000Z' };
const newMedia = { id: 'new-media', updated: '2026-09-10T00:00:00.000Z' };

test('deferred old media retains its checkpoint until its missing parent can be restored', async () => {
  const h = cursorHarness([oldMedia, newMedia]);
  assert.equal(await h.engine.pullCollection('media', async row => row.id !== oldMedia.id), false);
  assert.equal(h.checkpoint(), '2026-08-01T00:00:00.000Z');
  const restored = [];
  assert.equal(await h.engine.pullCollection('media', async row => { restored.push(row.id); }), true);
  assert.deepEqual(restored, ['old-media', 'new-media']);
  assert.equal(h.checkpoint(), newMedia.updated);
});

test('a strict full restore reports deferred records and keeps the old checkpoint', async () => {
  const h = cursorHarness([oldMedia], [newMedia]);
  h.engine.strictPullFailures = true;
  await assert.rejects(h.engine.pullCollection('media', async () => false), /保留游标/);
  assert.equal(h.checkpoint(), '2026-08-01T00:00:00.000Z');
});

test('successful merges advance through both records and tombstones', async () => {
  const h = cursorHarness([oldMedia], [newMedia]);
  assert.equal(await h.engine.pullCollection('media', async () => true), true);
  assert.equal(h.checkpoint(), newMedia.updated);
});

test('an early tombstone failure is handled while the active request remains pending', async () => {
  const h = cursorHarness([]);
  let release;
  h.context.APIClient.shared.fetchRecords = () => new Promise(resolve => { release = resolve; });
  h.context.APIClient.shared.fetchDeletedTombstones = async () => { throw new Error('offline'); };
  const outcome = h.engine.pullCollection('media', async () => {});
  await new Promise(resolve => setImmediate(resolve));
  release([]);
  assert.equal(await outcome, false);
  assert.equal(h.checkpoint(), '2026-08-01T00:00:00.000Z');
});

const columns = ['id', 'remoteId', 'title', 'note', 'firstPersonNote', 'happenedAt',
  'locationName', 'latitude', 'longitude', 'authorRole', 'moodRaw', 'syncState',
  'isArchived', 'inStorybook', 'editedAt', 'createdAt'];
function entryHarness() {
  const h = harness();
  const sql = new DatabaseSync(':memory:');
  sql.exec(`CREATE TABLE entry (${columns.map(column => `${column} ${['happenedAt', 'latitude', 'longitude', 'isArchived', 'inStorybook', 'editedAt', 'createdAt'].includes(column) ? 'NUMERIC' : 'TEXT'}`).join(',')})`);
  const original = { id: 'entry-1', happenedAt: 1, createdAt: 1, editedAt: 1,
    authorRole: 'parent', note: 'old text', isArchived: false, inStorybook: false, syncState: 'local' };
  sql.prepare(`INSERT INTO entry VALUES (${columns.map(() => '?').join(',')})`)
    .run(...columns.map(key => typeof original[key] === 'boolean' ? Number(original[key]) : original[key] ?? null));
  class Predicates {
    terms = [];
    constructor(table) { assert.equal(table, 'entry'); }
    equalTo(column, value) { this.terms.push([column, value]); return this; }
    isNull(column) { this.terms.push([column, null]); return this; }
  }
  h.context.relationalStore = { RdbPredicates: Predicates };
  h.database.store = { update: async (fields, predicate) => {
    if (h.beforeWrite) h.beforeWrite();
    const keys = Object.keys(fields);
    const where = predicate.terms.map(([key, value]) => `${key} ${value === null ? 'IS NULL' : '= ?'}`).join(' AND ');
    const result = sql.prepare(`UPDATE entry SET ${keys.map(key => `${key} = ?`).join(', ')} WHERE ${where}`)
      .run(...keys.map(key => fields[key]), ...predicate.terms.filter(([, value]) => value !== null).map(([, value]) => value));
    return Number(result.changes);
  } };
  h.database.fetchEntries = async () => {
    const row = sql.prepare('SELECT * FROM entry').get();
    if (!row) return [];
    return [Object.fromEntries(Object.entries(row).map(([key, value]) => [key,
      ['isArchived', 'inStorybook'].includes(key) ? value === 1 : value === null ? undefined : value]))];
  };
  h.context.Database.shared = h.database;
  h.context.APIClient = {
    syncTimestampString: date => date.toISOString(), remoteWasNewer: () => false,
    shared: { upsert: async () => ({ id: 'remote-entry' }) }
  };
  h.row = () => sql.prepare('SELECT * FROM entry').get();
  h.change = (key, value) => sql.prepare(`UPDATE entry SET ${key} = ?`).run(value);
  h.close = () => sql.close();
  return h;
}

test('unchanged upload snapshots are acknowledged normally', async () => {
  const h = entryHarness();
  try {
    await h.engine.pushEntries();
    assert.equal(h.row().syncState, 'synced');
    assert.equal(h.row().remoteId, 'remote-entry');
  } finally { h.close(); }
});

test('upload success, conflict, and failure cannot overwrite an edit made during the request', async () => {
  for (const result of ['success', 'remote-newer', 'failure']) {
    const h = entryHarness();
    try {
      h.context.APIClient.remoteWasNewer = () => result === 'remote-newer';
      h.context.APIClient.shared.upsert = async () => {
        h.change('note', 'new edit during request');
        if (result === 'failure') throw new Error('offline');
        return { id: 'remote-entry', note: 'remote old text' };
      };
      await h.engine.pushEntries();
      assert.equal(h.row().note, 'new edit during request', result);
      assert.equal(h.row().syncState, 'local', result);
    } finally { h.close(); }
  }
});

test('an unchanged snapshot accepts a newer remote payload or records a failed upload', async () => {
  for (const result of ['remote-newer', 'failure']) {
    const h = entryHarness();
    try {
      h.context.APIClient.remoteWasNewer = () => result === 'remote-newer';
      h.context.APIClient.shared.upsert = async () => {
        if (result === 'failure') throw new Error('offline');
        return { id: 'remote-entry', note: 'newer remote text' };
      };
      await h.engine.pushEntries();
      assert.equal(h.row().note, result === 'remote-newer' ? 'newer remote text' : 'old text');
      assert.equal(h.row().syncState, result === 'remote-newer' ? 'synced' : 'failed');
    } finally { h.close(); }
  }
});

test('conditional acknowledgement checks every payload field even when editedAt has not changed', async () => {
  const changes = { title: 'new title', note: 'new note', firstPersonNote: 'new first-person note',
    happenedAt: 5, locationName: 'new place', latitude: 5, longitude: 5,
    authorRole: 'other parent', moodRaw: 'happy', isArchived: 1, inStorybook: 1, editedAt: 5, createdAt: 5 };
  for (const [key, value] of Object.entries(changes)) {
    const h = entryHarness();
    try {
      // Edit immediately before the SQL write, after any application-level reads.
      h.beforeWrite = () => h.change(key, value);
      await h.engine.pushEntries();
      assert.equal(h.row()[key], value, key);
      assert.equal(h.row().syncState, 'local', key);
    } finally { h.close(); }
  }
});

test('a deleted upload snapshot is never recreated by acknowledgement', async () => {
  const h = entryHarness();
  try {
    h.context.APIClient.shared.upsert = async () => {
      h.change('id', 'replacement-entry');
      return { id: 'remote-entry' };
    };
    await h.engine.pushEntries();
    assert.equal(h.row().id, 'replacement-entry');
    assert.equal(h.row().syncState, 'local');
  } finally { h.close(); }
});

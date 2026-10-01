import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import vm from 'node:vm';
import { laterServerTimestamp } from '../entry/src/main/ets/sync/SyncCursor.ts';

// Production reads, serializers, conditional DELETE, cascade, rollback and cleanup ordering.
// Only Harmony SDK and filesystem I/O are adapted to disposable SQLite/fake file paths.
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, `Missing production method ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const models = [
  ['entries', 'entry', 'entry', 'fetchEntries', 'note', { happenedAt: 1, authorRole: 'parent', note: 'original', isArchived: false }],
  ['media', 'media', 'media', 'fetchAllMedia', 'contentHash', { entryId: 'parent', typeRaw: 'photo', localFileName: 'photo.jpg', thumbnailFileName: 'thumb.jpg', uploadProgress: 1, aiTags: [], contentHash: 'original' }],
  ['milestones', 'milestone', 'milestone', 'fetchMilestones', 'title', { title: 'original', category: 'custom', emoji: '*', isCustom: true }],
  ['firsttimes', 'first_time', 'firstTime', 'fetchFirstTimes', 'what', { what: 'original', happenedAt: 1 }],
  ['healthrecords', 'health_record', 'health', 'fetchHealth', 'title', { kind: 'other', title: 'original', recordedAt: 1, tags: [] }],
  ['vaccinerecords', 'vaccine_record', 'vaccine', 'fetchVaccines', 'vaccineName', { vaccineName: 'original', injectedAt: 1, source: 'manual', updatedAt: 1 }],
  ['growthmeasurements', 'growth_measurement', 'growth', 'fetchGrowth', 'note', { measuredAt: 1, note: 'original', source: 'manual', updatedAt: 1 }],
  ['comments', 'comment', 'comment', 'fetchCommentsForEntry', 'text', { entryId: 'parent', authorRole: 'parent', text: 'original', voiceFileName: 'comment.m4a', voiceDuration: 1.25, voiceWaveform: [] }],
  ['voicenotes', 'voice_note', 'voiceNote', 'fetchVoiceForEntry', 'transcript', { entryId: 'parent', authorRole: 'parent', transcript: 'original', localFileName: 'note.m4a', durationSeconds: 1.25, waveformSamples: [] }],
  ['voicememos', 'voice_memo', 'voiceMemo', 'fetchVoiceMemos', 'transcript', { kindRaw: 'other', transcript: 'original', recordedAt: 1, localFileName: 'memo.m4a' }],
  ['timecapsules', 'time_capsule', 'capsule', 'fetchCapsules', 'title', { title: 'original', fromRole: 'parent', unlockAt: 1, isLocked: true, encryptedBlobFileName: 'letter.capsule' }]
];
const dbNames = [...models.map(m => `${m[2]}Fields`), ...models.map(m => m[3]),
  'fetchMediaForEntry', 'rowToEntry', 'rowToMedia', 'optStr', 'optNum',
  'deleteSyncedFieldsIfUnchanged', 'syncedDeletionPredicates', 'updateEntryFields', 'insertMedia'];
const engineNames = ['removeSyncedLocal', 'removeRemoteTombstones', 'pullCollection', 'recordLocalId', 'rStr'];
const schema = [...method(database, 'createTables').matchAll(/s\.executeSql\(`(CREATE TABLE[\s\S]*?)`\)/g)].map(match => match[1]);

async function harness(collection = 'entries') {
  const dir = await mkdtemp(join(tmpdir(), 'bubu-tombstone-'));
  const path = join(dir, 'synthetic.sqlite');
  const sql = new DatabaseSync(path);
  sql.exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=0');
  for (const statement of schema) sql.exec(statement);
  sql.exec('ALTER TABLE time_capsule ADD COLUMN cryptoVersion INTEGER');
  const competitor = new DatabaseSync(path);
  competitor.exec('PRAGMA busy_timeout=0');
  const events = [];
  const h = { events, sql, competitor, collection };
  const context = vm.createContext({ Date, Map, Set, Error, Promise, Object, JSON, laterServerTimestamp,
    DOMAIN: 0, hilog: { warn() {}, error() {} },
    SyncState: { local: 'local', synced: 'synced', failed: 'failed', uploading: 'uploading' },
    MediaStore: { shared: { deleteLocalFiles: (...files) => {
      for (const file of files.filter(Boolean)) events.push(`file:${file}`);
    } } }
  });
  class Predicates {
    terms = [];
    constructor(table) { this.table = table; }
    equalTo(key, value) { this.terms.push([key, value]); return this; }
    isNull(key) { this.terms.push([key, null]); return this; }
    orderByAsc() { return this; }
    orderByDesc() { return this; }
  }
  context.relationalStore = { RdbPredicates: Predicates };
  vm.runInContext(stripTypeScriptTypes(`
    class AppDatabase { ${dbNames.map(name => method(database, name)).join('\n')} }
    class SyncEngine { ${engineNames.map(name => method(sync, name)).join('\n')} }
    globalThis.Database = AppDatabase; globalThis.Engine = SyncEngine;
  `), context);
  const db = new context.Database();
  context.Database.shared = db;
  context.Engine.errorText = error => error.message;
  context.Engine.isMissingOptionalCollectionError = () => false;
  const where = p => p.terms.length ? ` WHERE ${p.terms.map(([key, value]) => `${key} ${value === null ? 'IS NULL' : '= ?'}`).join(' AND ')}` : '';
  const params = p => p.terms.filter(([, value]) => value !== null).map(([, value]) => value);
  function fault(name) { if (h.failAt === name) throw new Error(`synthetic failure ${name}`); }
  function query(predicate, transaction = false) {
    const name = `query:${predicate.table}`;
    if (transaction) { events.push(name); fault(name); }
    const rows = sql.prepare(`SELECT * FROM ${predicate.table}${where(predicate)}`).all(...params(predicate));
    if (!transaction && h.afterRead) h.afterRead(predicate.table);
    let index = -1;
    const columns = sql.prepare(`PRAGMA table_info(${predicate.table})`).all().map(row => row.name);
    return { rowCount: rows.length, goToNextRow: () => ++index < rows.length,
      getColumnIndex: key => { assert.ok(columns.includes(key), key); return columns.indexOf(key); },
      isColumnNull: column => rows[index][columns[column]] === null,
      getString: column => String(rows[index][columns[column]] ?? ''),
      getLong: column => Math.trunc(Number(rows[index][columns[column]])),
      getDouble: column => Number(rows[index][columns[column]]), close() {} };
  }
  // Transaction owns a dedicated connection; ordinary writes on the same RdbStore
  // use its ordinary connection and receive 14800024 while the transaction writes.
  // This models the official Transaction API contract; native SDK validation is separate.
  function ordinaryWrite(statement, values) {
    try { return Number(competitor.prepare(statement).run(...values).changes); }
    catch (error) { if (/locked|busy/i.test(error.message)) error.code = 14800024; throw error; }
  }
  db.store = {
    update: async (fields, predicate) => ordinaryWrite(
      `UPDATE ${predicate.table} SET ${Object.keys(fields).map(key => `${key} = ?`).join(',')}${where(predicate)}`,
      [...Object.values(fields), ...params(predicate)]),
    insert: async (table, fields) => ordinaryWrite(
      `INSERT INTO ${table} (${Object.keys(fields).join(',')}) VALUES (${Object.keys(fields).map(() => '?').join(',')})`, Object.values(fields)),
    query: async predicate => query(predicate),
    createTransaction: async () => {
      if (h.beforeTransaction) h.beforeTransaction();
      sql.exec('BEGIN DEFERRED');
      events.push('begin');
      return {
        delete: async predicate => {
          const name = `delete:${predicate.table}`;
          if (h.beforeDelete) h.beforeDelete(predicate.table);
          events.push(name); fault(name);
          const changes = Number(sql.prepare(`DELETE FROM ${predicate.table}${where(predicate)}`).run(...params(predicate)).changes);
          if (h.afterDelete) await h.afterDelete(predicate.table);
          return changes;
        },
        querySql: async (statement, args) => {
          const table = /SELECT id FROM (\w+) WHERE entryId = \?/.exec(statement)?.[1];
          assert.ok(table, statement);
          return query(new Predicates(table).equalTo('entryId', args[0]), true);
        },
        commit: async () => { fault('commit'); sql.exec('COMMIT'); events.push('commit'); },
        rollback: async () => { sql.exec('ROLLBACK'); events.push('rollback'); }
      };
    }
  };
  h.insert = (table, fields, connection = sql) => {
    connection.prepare(`INSERT INTO ${table} (${Object.keys(fields).join(',')}) VALUES (${Object.keys(fields).map(() => '?').join(',')})`).run(...Object.values(fields));
  };
  h.model = (name, id) => {
    const item = models.find(m => m[0] === name);
    return { id, remoteId: `remote-${id}`, syncState: 'synced', createdAt: 1, ...item[5] };
  };
  h.seed = (name, id, overrides = {}, connection = sql) => {
    const item = models.find(m => m[0] === name);
    const row = { ...h.model(name, id), ...overrides };
    h.insert(item[1], context.Database[`${item[2]}Fields`](row), connection);
    return row;
  };
  h.seed('entries', 'parent');
  if (collection === 'entries') {
    h.seed('media', 'photo'); h.seed('voicenotes', 'note'); h.seed('comments', 'comment');
  } else h.seed(collection, 'target');
  h.insert('feed_event', { id: 'feed', kind: 'test', actorRole: 'parent', summary: 'synthetic', targetLocalId: collection === 'entries' ? 'parent' : 'target', happenedAt: 1 });
  h.insert('feed_event', { id: 'other-feed', kind: 'test', actorRole: 'parent', summary: 'unrelated', targetLocalId: 'other', happenedAt: 1 });
  h.table = models.find(m => m[0] === collection)[1];
  h.id = collection === 'entries' ? 'parent' : 'target';
  h.rows = table => sql.prepare(`SELECT * FROM ${table} ORDER BY id`).all();
  h.snapshot = () => JSON.stringify(['entry', 'media', 'voice_note', 'comment', 'feed_event', h.table].map(table => h.rows(table)));
  h.edit = (table, id, field, value, connection = competitor) => connection.prepare(`UPDATE ${table} SET ${field} = ? WHERE id = ?`).run(value, id);
  h.engine = new context.Engine();
  h.db = db;
  h.context = context;
  h.remove = () => h.engine.removeSyncedLocal(collection, h.id);
  h.close = async () => { competitor.close(); sql.close(); await rm(dir, { recursive: true, force: true }); };
  return h;
}

function noFiles(h) { assert.equal(h.events.some(event => event.startsWith('file:')), false); }

test('unchanged synced Entry and exact children delete atomically before cleaning files', async () => {
  const h = await harness();
  try {
    assert.equal(await h.remove(), true);
    for (const table of ['entry', 'media', 'voice_note', 'comment']) assert.equal(h.rows(table).length, 0);
    assert.deepEqual(h.rows('feed_event').map(row => row.id), ['other-feed']);
    assert.deepEqual(h.events.filter(event => event.startsWith('file:')).sort(), ['file:comment.m4a', 'file:note.m4a', 'file:photo.jpg', 'file:thumb.jpg']);
    assert.ok(h.events.findIndex(event => event.startsWith('file:')) > h.events.indexOf('commit'));
  } finally { await h.close(); }
});

test('an Entry edit during awaited child reads is preserved even without changing syncState', async () => {
  for (const dirty of [false, true]) {
    const h = await harness();
    try {
      h.afterRead = table => {
        if (table === 'media') {
          h.edit('entry', 'parent', 'note', 'new edit');
          if (dirty) h.edit('entry', 'parent', 'syncState', 'local');
        }
      };
      assert.equal(await h.remove(), false);
      assert.equal(h.rows('entry')[0].note, 'new edit');
      for (const table of ['media', 'voice_note', 'comment']) assert.equal(h.rows(table).length, 1);
      assert.ok(h.events.includes('rollback')); noFiles(h);
    } finally { await h.close(); }
  }
});

for (const [collection, table, , , field] of models.filter(item => ['media', 'comments', 'voicenotes'].includes(item[0]))) {
  const id = { media: 'photo', comments: 'comment', voicenotes: 'note' }[collection];
  test(`${collection}: dirty children defer the parent tombstone without deleting rows or files`, async () => {
    for (const state of ['local', 'failed', 'uploading']) {
      const h = await harness();
      try {
        h.edit(table, id, 'syncState', state);
        const before = h.snapshot();
        assert.equal(await h.remove(), false);
        assert.equal(h.snapshot(), before); noFiles(h);
      } finally { await h.close(); }
    }
  });
  test(`${collection}: child edits and removals after snapshot roll back the parent deletion`, async () => {
    for (const change of ['edit', 'remove']) {
      const h = await harness();
      try {
        let expected;
        h.beforeTransaction = () => {
          if (change === 'edit') h.edit(table, id, field, 'new child edit');
          else h.competitor.prepare(`DELETE FROM ${table} WHERE id = ?`).run(id);
          expected = h.snapshot();
        };
        assert.equal(await h.remove(), false);
        assert.equal(h.snapshot(), expected); assert.ok(h.events.includes('rollback')); noFiles(h);
      } finally { await h.close(); }
    }
  });
  test(`${collection}: newly added children are never swept up by the cascade`, async () => {
    for (const state of ['synced', 'local']) {
      const h = await harness();
      try {
        let expected;
        h.beforeTransaction = () => {
          h.seed(collection, 'new-child', { syncState: state }, h.competitor);
          expected = h.snapshot();
        };
        assert.equal(await h.remove(), false);
        assert.equal(h.snapshot(), expected); assert.ok(h.events.includes('rollback')); noFiles(h);
      } finally { await h.close(); }
    }
  });
}

test('a competing parent edit immediately before the first DELETE defeats its predicate', async () => {
  const h = await harness();
  try {
    h.beforeDelete = table => { if (table === 'entry') h.edit('entry', 'parent', 'note', 'last instant'); };
    assert.equal(await h.remove(), false);
    assert.equal(h.rows('entry')[0].note, 'last instant'); noFiles(h);
  } finally { await h.close(); }
});

test('the first conditional DELETE holds the SQLite writer lock through child census and commit', async () => {
  const h = await harness();
  try {
    let verified = 0;
    h.afterDelete = table => {
      if (table === 'entry') {
        assert.throws(() => h.edit('entry', 'parent', 'note', 'concurrent'), /locked|busy/i);
        assert.throws(() => h.seed('media', 'concurrent-child', {}, h.competitor), /locked|busy/i);
        verified++;
      }
    };
    assert.equal(await h.remove(), true);
    assert.equal(verified, 1);
  } finally { await h.close(); }
});

test('child-delete, child-query, feed-delete and commit failures roll back the entire cascade', async () => {
  for (const failure of ['delete:entry', 'delete:media', 'delete:voice_note', 'delete:comment',
    'query:media', 'query:voice_note', 'query:comment', 'delete:feed_event', 'commit']) {
    const h = await harness();
    try {
      const before = h.snapshot(); h.failAt = failure;
      await assert.rejects(h.remove(), /synthetic failure/);
      assert.equal(h.snapshot(), before, failure);
      assert.ok(h.events.includes('rollback'), failure); noFiles(h);
    } finally { await h.close(); }
  }
});

for (const [collection, table, , , field] of models.filter(item => item[0] !== 'entries')) {
  test(`${collection}: unchanged direct tombstones commit; stale snapshots preserve edits and files`, async () => {
    for (const edited of [false, true]) {
      const h = await harness(collection);
      try {
        if (edited) h.beforeTransaction = () => h.edit(table, 'target', field, 'new direct edit');
        assert.equal(await h.remove(), !edited);
        if (edited) { assert.equal(h.rows(table)[0][field], 'new direct edit'); noFiles(h); }
        else {
          assert.equal(h.rows(table).length, 0);
          const firstFile = h.events.findIndex(event => event.startsWith('file:'));
          if (firstFile >= 0) assert.ok(firstFile > h.events.indexOf('commit'));
        }
        assert.equal(h.rows('entry').length, 1);
      } finally { await h.close(); }
    }
  });
}

test('a rejected cascade retains the collection cursor and retries successfully after child sync', async () => {
  const h = await harness();
  try {
    h.edit('media', 'photo', 'syncState', 'local');
    let cursor = '2026-08-01T00:00:00.000Z';
    h.engine.getCursor = async () => cursor;
    h.engine.setCursor = async (_, next) => { cursor = next; };
    h.context.APIClient = { shared: {
      fetchRecords: async () => [{ id: 'unrelated', updated: '2026-09-10T00:00:00.000Z' }],
      fetchDeletedTombstones: async () => [{ id: 'remote-parent', localId: 'parent', updated: '2026-09-01T00:00:00.000Z' }]
    } };
    assert.equal(await h.engine.pullCollection('entries', async () => true), false);
    assert.equal(cursor, '2026-08-01T00:00:00.000Z'); noFiles(h);
    h.edit('media', 'photo', 'syncState', 'synced');
    assert.equal(await h.engine.pullCollection('entries', async () => true), true);
    assert.equal(cursor, '2026-09-10T00:00:00.000Z');
    assert.equal(h.rows('entry').length, 0);
  } finally { await h.close(); }
});


test('same shared RdbStore edit and child insertion cannot join the tombstone transaction', async () => {
  const h = await harness();
  try {
    let attempts = 0;
    h.afterDelete = async table => {
      if (table !== 'entry') return;
      await assert.rejects(h.context.Database.shared.updateEntryFields('parent', { note: 'reentrant edit', syncState: 'local' }),
        error => error.code === 14800024);
      await assert.rejects(h.context.Database.shared.insertMedia(h.model('media', 'reentrant-child')),
        error => error.code === 14800024);
      attempts += 2;
    };
    assert.equal(await h.remove(), true);
    assert.equal(attempts, 2);
    assert.equal(h.rows('media').length, 0);
    assert.ok(h.events.indexOf('commit') < h.events.findIndex(event => event.startsWith('file:')));
  } finally { await h.close(); }
});

for (const collection of ['entries', 'media', 'voicenotes', 'comments']) {
  test(`${collection}: deletion guards compare every persisted field at the transaction boundary`, async () => {
    const initial = await harness(collection);
    const table = initial.table;
    const columns = Object.keys(initial.rows(table)[0]);
    await initial.close();
    for (const field of columns) {
      const h = await harness(collection);
      try {
        let expected;
        const row = h.rows(table)[0];
        const value = typeof row[field] === 'number' ? row[field] + 1 : `changed-${field}`;
        h.beforeTransaction = () => { h.edit(table, h.id, field, value); expected = h.snapshot(); };
        assert.equal(await h.remove(), false, field);
        assert.equal(h.snapshot(), expected, field); noFiles(h);
      } finally { await h.close(); }
    }
  });
}

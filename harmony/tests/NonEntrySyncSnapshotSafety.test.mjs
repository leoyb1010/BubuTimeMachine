import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import vm from 'node:vm';
import { rememberCapsuleVersion } from '../entry/src/main/ets/services/security/CapsuleVersion.ts';

const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
function method(source, name, optional = false) {
  const expression = new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`, 'm');
  const start = source.search(expression);
  if (optional && start < 0) return '';
  assert.ok(start >= 0, `Missing production method: ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const cases = [
  ['ChildProfile', 'child_profile', 'upsertChildProfile', 'fetchChildProfile', 'pushChildProfile', 'name',
    { name: 'Synthetic child', birthday: 1 }],
  ['Milestone', 'milestone', 'upsertMilestone', 'fetchMilestones', 'pushMilestones', 'title',
    { title: 'Synthetic milestone', category: 'custom', emoji: '*', isCustom: true }],
  ['FirstTime', 'first_time', 'insertFirstTime', 'fetchFirstTimes', 'pushFirstTimes', 'what',
    { what: 'Synthetic first', happenedAt: 1, detectedByAI: false, confirmedByParent: true }],
  ['Member', 'family_member', 'upsertMember', 'fetchMembers', 'pushFamilyMembers', 'name',
    { name: 'Synthetic parent', relation: 'parent', avatarEmoji: '*', themeColorHex: '#000000' }],
  ['Health', 'health_record', 'insertHealth', 'fetchHealth', 'pushHealthRecords', 'title',
    { kind: 'other', title: 'Synthetic health', recordedAt: 1, tags: [] }],
  ['Vaccine', 'vaccine_record', 'insertVaccine', 'fetchVaccines', 'pushVaccineRecords', 'vaccineName',
    { vaccineName: 'Synthetic vaccine', injectedAt: 1, source: 'manual', updatedAt: 1 }],
  ['Growth', 'growth_measurement', 'insertGrowth', 'fetchGrowth', 'pushGrowthMeasurements', 'note',
    { measuredAt: 1, note: 'Synthetic growth', source: 'manual', updatedAt: 1 }],
  ['Comment', 'comment', 'insertComment', 'fetchCommentsForEntry', 'pushComments', 'text',
    { entryId: 'entry-1', authorRole: 'parent', text: 'Synthetic comment', voiceDuration: 0, voiceWaveform: [] }],
  ['VoiceNote', 'voice_note', 'insertVoiceNote', 'fetchVoiceForEntry', 'pushVoiceNotes', 'transcript',
    { entryId: 'entry-1', authorRole: 'parent', transcript: 'Synthetic note', durationSeconds: 1, waveformSamples: [] }],
  ['VoiceMemo', 'voice_memo', 'insertVoiceMemo', 'fetchVoiceMemos', 'pushVoiceMemos', 'transcript',
    { kindRaw: 'other', transcript: 'Synthetic memo', recordedAt: 1 }],
  ['Capsule', 'time_capsule', 'insertCapsule', 'fetchCapsules', 'pushTimeCapsules', 'title',
    { title: 'Synthetic capsule', fromRole: 'parent', unlockAt: 1, isLocked: true }]
];
const engineNames = [...cases.map(item => item[4]), ...cases.map(item => `apply${item[0]}`),
  'replaceVoiceNote', 'replaceCapsule', 'vaccineHealthFallbackBody', 'growthHealthFallbackBody',
  'remoteFileURL', 'rFileName', 'rStr', 'rNum', 'rBool', 'rDate', 'rStrArray', 'rNumArray', 'metricText',
  'pushUnsyncedMedia', 'pushMediaItem', 'updateMediaFields', 'updateMediaProgressIfUnchanged',
  'downloadMissingFiles', 'ensureLocalCapsuleBlob', 'extFromURL'];
const databaseNames = [...cases.map(item => item[2]), ...cases.map(item => item[3]),
  'insertMedia', 'fetchAllMedia', 'rowToMedia', 'optStr', 'optNum'];
const engineMethods = engineNames.map(name => method(sync, name)).join('\n');
const databaseMethods = [...databaseNames.map(name => method(database, name)),
  method(database, 'updateFieldsIfUnchanged', true),
  ...[...cases.map(item => item[0]), 'Media'].map(name => method(database, `${name[0].toLowerCase()}${name.slice(1)}Fields`, true))].join('\n');

async function harness(item, file = false) {
  const [kind, table, insert, fetch, push, editedField, details] = item;
  const context = vm.createContext({ Date, Map, Set, Error, Promise, Object, JSON, rememberCapsuleVersion,
    DOMAIN: 0, hilog: { warn() {}, error() {}, info() {} },
    MediaType: { video: 'video' },
    fileIo: { accessSync: () => false, unlinkSync() {}, renameSync() {} },
    CapsuleVault: { shared: { validateVersion: () => 1 } },
    SyncState: { local: 'local', synced: 'synced', failed: 'failed', uploading: 'uploading' },
    MediaStore: { publicUploadSoftLimitBytes: 999999, shared: { exists: () => file, fullPath: name => name,
      thumbnailExists: () => false, thumbnailPath: name => name, fileSizeForMedia: () => 1 } } });
  vm.runInContext(stripTypeScriptTypes(`
    class SyncEngine { ${engineMethods} }
    class AppDatabase { ${databaseMethods} }
    globalThis.Engine = SyncEngine; globalThis.Database = AppDatabase;
  `), context);
  const Engine = context.Engine;
  Engine.isDirty = state => state !== 'synced';
  Engine.isLocalPresetPlaceholder = () => false;
  Engine.isMissingOptionalCollectionError = () => false;
  Engine.errorText = error => error.message;
  const db = new context.Database();
  context.Database.shared = db;
  const sql = new DatabaseSync(':memory:');
  let columns;
  const h = { context, db, engine: new Engine(), table, push, editedField,
    original: { id: 'synthetic-1', syncState: 'local', createdAt: 1, ...details,
      ...(file ? { localFileName: 'synthetic.bin', avatarMediaFileName: 'synthetic.bin',
        voiceFileName: 'synthetic.bin', encryptedBlobFileName: 'synthetic.bin' } : {}) } };
  class Predicates {
    terms = [];
    constructor(name) { assert.equal(name, table); }
    equalTo(key, value) { this.terms.push([key, value]); return this; }
    isNull(key) { this.terms.push([key, null]); return this; }
    orderByAsc() { return this; }
    orderByDesc() { return this; }
  }
  context.relationalStore = { RdbPredicates: Predicates, ConflictResolution: { ON_CONFLICT_REPLACE: 5 } };
  db.store = {
    query: async predicate => {
      const rows = sql.prepare(`SELECT * FROM ${table}`).all().filter(row => predicate.terms.every(([key, value]) => row[key] === value));
      let index = -1;
      return { goToNextRow: () => ++index < rows.length, getColumnIndex: key => columns.indexOf(key),
        isColumnNull: column => rows[index][columns[column]] === null,
        getString: column => String(rows[index][columns[column]] ?? ''),
        getLong: column => Math.trunc(Number(rows[index][columns[column]])),
        getDouble: column => Number(rows[index][columns[column]]), close() {} };
    },
    insert: async (name, fields) => {
      assert.equal(name, table);
      if (!columns) {
        columns = Object.keys(fields);
        sql.exec(`CREATE TABLE ${table} (${columns.map(key => `${key} ${key === 'id' ? 'TEXT PRIMARY KEY' : ''}`).join(', ')})`);
      }
      sql.prepare(`INSERT OR REPLACE INTO ${table} (${Object.keys(fields).join(', ')}) VALUES (${Object.keys(fields).map(() => '?').join(', ')})`)
        .run(...Object.values(fields));
    },
    update: async (fields, predicate) => {
      if (h.beforeWrite) h.beforeWrite();
      const keys = Object.keys(fields);
      const where = predicate.terms.map(([key, value]) => `${key} ${value === null ? 'IS NULL' : '= ?'}`).join(' AND ');
      return Number(sql.prepare(`UPDATE ${table} SET ${keys.map(key => `${key} = ?`).join(', ')} WHERE ${where}`)
        .run(...Object.values(fields), ...predicate.terms.filter(([, value]) => value !== null).map(([, value]) => value)).changes);
    }
  };
  await db[insert](h.original);
  db.fetchEntries = async () => [{ id: 'entry-1' }];
  Object.defineProperty(db, 'raw', { get: () => db.store });
  context.APIClient = { syncTimestampString: date => date.toISOString(), remoteWasNewer: () => false,
    shared: { upsert: async () => ({ id: 'remote-1' }),
      uploadFile: async () => ({ recordId: 'remote-1', storedFileName: 'synthetic.bin' }),
      fileURL: () => 'synthetic://remote-file' } };
  h.row = () => sql.prepare(`SELECT * FROM ${table}`).get();
  h.change = (key, value) => sql.prepare(`UPDATE ${table} SET ${key} = ?`).run(value);
  h.remove = () => sql.exec(`DELETE FROM ${table}`);
  h.close = () => sql.close();
  return h;
}

for (const item of cases) {
  test(`${item[0]}: an unchanged successful upload is acknowledged`, async () => {
    const h = await harness(item);
    try {
      await h.engine[h.push]();
      assert.equal(h.row().syncState, 'synced');
      assert.equal(h.row().remoteId, 'remote-1');
    } finally { h.close(); }
  });
  test(`${item[0]}: request success, conflict and failure preserve newer local edits`, async () => {
    for (const result of ['success', 'remote-newer', 'failure']) {
      const h = await harness(item);
      try {
        h.context.APIClient.remoteWasNewer = () => result === 'remote-newer';
        h.context.APIClient.shared.upsert = async () => {
          h.change(h.editedField, 'new local edit');
          if (result === 'failure') throw new Error('offline');
          return { id: 'remote-1', [h.editedField]: 'remote edit' };
        };
        await h.engine[h.push]();
        assert.equal(h.row()[h.editedField], 'new local edit', result);
        assert.equal(h.row().syncState, 'local', result);
      } finally { h.close(); }
    }
  });
  test(`${item[0]}: an upload acknowledgement cannot resurrect a deleted row`, async () => {
    const h = await harness(item);
    try {
      h.context.APIClient.shared.upsert = async () => { h.remove(); return { id: 'remote-1' }; };
      await h.engine[h.push]();
      assert.equal(h.row(), undefined);
    } finally { h.close(); }
  });
  test(`${item[0]}: same-timestamp changes to every stored field defeat the atomic acknowledgement`, async () => {
    const initial = await harness(item);
    const fields = Object.keys(initial.row()).filter(key => !['id', 'syncState', 'remoteId'].includes(key));
    initial.close();
    for (const key of fields) {
      const h = await harness(item);
      try {
        const old = h.row()[key];
        const value = typeof old === 'number' ? old + 1 : `changed ${key}`;
        h.beforeWrite = () => h.change(key, value);
        await h.engine[h.push]();
        assert.equal(h.row()[key], value, key);
        assert.equal(h.row().syncState, 'local', key);
      } finally { h.close(); }
    }
  });
}

for (const kind of ['ChildProfile', 'Comment', 'VoiceNote', 'VoiceMemo', 'Capsule']) {
  test(`${kind}: edits during the second file-upload await remain dirty`, async () => {
    const h = await harness(cases.find(item => item[0] === kind), true);
    try {
      h.context.APIClient.shared.uploadFile = async () => {
        h.change(h.editedField, 'edit during file upload');
        return { recordId: 'remote-1', storedFileName: 'synthetic.bin' };
      };
      await h.engine[h.push]();
      assert.equal(h.row()[h.editedField], 'edit during file upload');
      assert.equal(h.row().syncState, 'local');
    } finally { h.close(); }
  });
}

for (const kind of ['Vaccine', 'Growth']) {
  test(`${kind}: optional-collection fallback acknowledgements preserve concurrent edits`, async () => {
    for (const fail of [false, true]) {
      const h = await harness(cases.find(item => item[0] === kind));
      try {
        h.context.Engine.isMissingOptionalCollectionError = () => true;
        h.context.APIClient.shared.upsert = async collection => {
          if (collection !== 'healthrecords') throw new Error('collection missing');
          h.change(h.editedField, 'edit during fallback');
          if (fail) throw new Error('offline');
          return { id: 'fallback-1' };
        };
        await h.engine[h.push]();
        assert.equal(h.row()[h.editedField], 'edit during fallback');
        assert.equal(h.row().syncState, 'local');
      } finally { h.close(); }
    }
  });
}

for (const item of cases) {
  test(`${item[0]}: unchanged conflict payloads and failures still commit`, async () => {
    for (const result of ['remote-newer', 'failure']) {
      const h = await harness(item);
      try {
        h.context.APIClient.remoteWasNewer = () => result === 'remote-newer';
        h.context.APIClient.shared.upsert = async () => {
          if (result === 'failure') throw new Error('offline');
          return { id: 'remote-1', [h.editedField]: 'remote edit' };
        };
        await h.engine[h.push]();
        assert.equal(h.row().syncState, result === 'remote-newer' ? 'synced' : 'failed');
        assert.equal(h.row()[h.editedField], result === 'remote-newer' ? 'remote edit' : h.original[h.editedField]);
      } finally { h.close(); }
    }
  });
}

const mediaCase = ['Media', 'media', 'insertMedia', 'fetchAllMedia', 'pushUnsyncedMedia', 'contentHash',
  { entryId: 'entry-1', typeRaw: 'photo', aiTags: [], uploadProgress: 0, contentHash: 'old-hash' }];

test('Media: progress does not block completion and late callbacks cannot change a completed row', async () => {
  const h = await harness(mediaCase, true);
  try {
    let progress;
    h.context.APIClient.shared.uploadFile = async (...args) => {
      progress = args[6];
      progress(0.5);
      assert.equal(h.row().uploadProgress, 0.5);
      return { recordId: 'remote-1', storedFileName: 'synthetic.bin' };
    };
    await h.engine[h.push]();
    assert.equal(h.row().syncState, 'synced');
    assert.equal(h.row().remoteId, 'remote-1');
    assert.equal(h.row().uploadProgress, 1);
    progress(0.75);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(h.row().uploadProgress, 1);
  } finally { h.close(); }
});

test('Media: completion, failure and progress preserve an edit during upload', async () => {
  for (const fail of [false, true]) {
    const h = await harness(mediaCase, true);
    try {
      h.context.APIClient.shared.uploadFile = async (...args) => {
        h.change('contentHash', 'new-local-hash');
        h.change('syncState', 'local');
        args[6](0.8);
        if (fail) throw new Error('offline');
        return { recordId: 'remote-1', storedFileName: 'synthetic.bin' };
      };
      await h.engine[h.push]();
      assert.equal(h.row().contentHash, 'new-local-hash');
      assert.equal(h.row().syncState, 'local');
      assert.equal(h.row().remoteId, null);
      assert.equal(h.row().uploadProgress, 0);
    } finally { h.close(); }
  }
});

test('Media: a concurrent change to every persistent field prevents starting the stale upload', async () => {
  const initial = await harness(mediaCase, true);
  const fields = Object.keys(initial.row()).filter(key => !['id', 'uploadProgress'].includes(key));
  initial.close();
  for (const key of fields) {
    const h = await harness(mediaCase, true);
    try {
      let requests = 0;
      h.context.APIClient.shared.uploadFile = async () => { requests++; throw new Error('unexpected upload'); };
      const old = h.row()[key];
      const value = typeof old === 'number' ? old + 1 : `changed ${key}`;
      h.beforeWrite = () => h.change(key, value);
      await h.engine[h.push]();
      assert.equal(h.row()[key], value, key);
      assert.equal(requests, 0, key);
      assert.equal(h.row().syncState, key === 'syncState' ? value : 'local', key);
    } finally { h.close(); }
  }
});

test('Media: removed upload targets stay removed', async () => {
  const h = await harness(mediaCase, true);
  try {
    h.context.APIClient.shared.uploadFile = async () => {
      h.remove();
      return { recordId: 'remote-1', storedFileName: 'synthetic.bin' };
    };
    await h.engine[h.push]();
    assert.equal(h.row(), undefined);
  } finally { h.close(); }
});

test('Media: unchanged missing files and failed uploads are marked failed', async () => {
  for (const exists of [false, true]) {
    const h = await harness(mediaCase, true);
    try {
      h.context.MediaStore.shared.exists = () => exists;
      h.context.APIClient.shared.uploadFile = async () => { throw new Error('offline'); };
      await h.engine[h.push]();
      assert.equal(h.row().syncState, 'failed');
      assert.ok(h.row().syncFailureReason.length > 0);
    } finally { h.close(); }
  }
});

test('the shared acknowledgement helper rejects unknown tables and unbounded snapshots', async () => {
  const h = await harness(cases[0]);
  try {
    await assert.rejects(h.db.updateFieldsIfUnchanged('pending_deletion', { id: 'synthetic-1', syncState: 'local' }, {}));
    await assert.rejects(h.db.updateFieldsIfUnchanged('child_profile', {}, {}));
    await assert.rejects(h.db.updateFieldsIfUnchanged('child_profile', { id: 'synthetic-1' }, {}));
    await assert.rejects(h.db.updateFieldsIfUnchanged('child_profile', { id: 'synthetic-1', syncState: 'local', payload: {} }, {}));
  } finally { h.close(); }
});

test('fractional VoiceNote duration round-trips through the production read before acknowledgement', async () => {
  const item = cases.find(item => item[0] === 'VoiceNote');
  const h = await harness(item);
  try {
    h.change('durationSeconds', 1.25);
    await h.engine[h.push]();
    assert.equal(h.row().durationSeconds, 1.25);
    assert.equal(h.row().syncState, 'synced');
  } finally { h.close(); }
});


for (const kind of ['ChildProfile', 'Comment', 'VoiceNote', 'VoiceMemo', 'Capsule', 'Media']) {
  test(`${kind}: downloaded attachments never overwrite edits or resurrect deletions`, async () => {
    for (const outcome of ['unchanged', 'edit', 'delete']) {
      const item = kind === 'Media' ? mediaCase : cases.find(item => item[0] === kind);
      const h = await harness(item);
      try {
        const localField = kind === 'ChildProfile' ? 'avatarMediaFileName' : kind === 'Comment' ? 'voiceFileName'
          : kind === 'Capsule' ? 'encryptedBlobFileName' : 'localFileName';
        if (kind !== 'Capsule') h.change(kind === 'ChildProfile' ? 'avatarRemoteURL' : 'remoteURL', 'synthetic://remote.bin');
        if (kind === 'Media') h.change('contentHash', null);
        for (const [model, fetch] of [['Media', 'fetchAllMedia'], ['VoiceNote', 'fetchVoiceForEntry'],
          ['VoiceMemo', 'fetchVoiceMemos'], ['Comment', 'fetchCommentsForEntry'], ['ChildProfile', 'fetchChildProfile']]) {
          if (kind !== model) h.db[fetch] = async () => model === 'ChildProfile' ? null : [];
        }
        let downloads = 0;
        h.context.APIClient.shared.downloadFile = async () => {
          downloads++;
          if (outcome === 'edit') { h.change(h.editedField, 'edit during download'); h.change('syncState', 'local'); }
          if (outcome === 'delete') h.remove();
        };
        if (kind === 'Capsule') {
          const capsule = (await h.db.fetchCapsules())[0];
          await h.engine.ensureLocalCapsuleBlob(capsule, { encryptedBlobRemoteURL: 'synthetic://remote.bin' });
        } else {
          await h.engine.downloadMissingFiles();
        }
        assert.equal(downloads, 1);
        if (outcome === 'delete') assert.equal(h.row(), undefined);
        else if (outcome === 'edit') {
          assert.equal(h.row()[h.editedField], 'edit during download');
          assert.equal(h.row().syncState, 'local');
          assert.equal(h.row()[localField], null);
        } else assert.ok(h.row()[localField]?.length > 0);
      } finally { h.close(); }
    }
  });
}

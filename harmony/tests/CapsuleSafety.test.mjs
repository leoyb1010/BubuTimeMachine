import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const view = await readFile(new URL('../entry/src/main/ets/view/CapsuleRecoveryView.ets', import.meta.url), 'utf8');
const vault = await readFile(new URL('../entry/src/main/ets/services/security/CapsuleVault.ets', import.meta.url), 'utf8');
const media = await readFile(new URL('../entry/src/main/ets/services/MediaStore.ets', import.meta.url), 'utf8');
const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');

test('恢复码必须正好 24 词且全部属于内置词表', () => {
  assert.ok(view.includes('this.normalizedWords().length === 24'));
  assert.ok(view.includes('!CapsuleRecovery.wordList.includes(word)'));
  assert.ok(view.indexOf('badWords.length > 0') < view.indexOf('this.commitRestore(candidate)'));
});

test('有 v3 胶囊时必须试解成功才覆盖，无样本且已有不同码必须二次确认', () => {
  assert.ok(vault.includes('async canDecryptV3'));
  assert.ok(view.includes('await CapsuleVault.shared.canDecryptV3'));
  assert.ok(view.includes("title: '覆盖现有恢复码？'"));
  assert.ok(view.includes('正确前不会覆盖原恢复码'));
});

test('胶囊更新使用 upsert，解封语音只写入固定 cache 临时文件', () => {
  assert.ok(db.includes("insert('time_capsule', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)"));
  assert.ok(vault.includes('this.mediaStore.materializeCapsuleVoice(data, salt, ext)'));
  assert.ok(media.includes("context.cacheDir + '/CapsuleScratch'"));
  assert.ok(media.includes('capsule-voice-${safeSalt}'));
  assert.ok(!vault.includes('payload.voiceFileName = this.saveBlob(bytes, ext)'));
});

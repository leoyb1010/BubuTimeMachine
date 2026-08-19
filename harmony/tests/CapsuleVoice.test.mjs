import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../entry/src/main/ets/view/CapsuleComposeView.ets', import.meta.url), 'utf8');
const unlock = await readFile(new URL('../entry/src/main/ets/view/CapsuleUnlockView.ets', import.meta.url), 'utf8');
const vault = await readFile(new URL('../entry/src/main/ets/services/security/CapsuleVault.ets', import.meta.url), 'utf8');

test('胶囊语音与文字进入同一加密载荷，封存后删除明文并在解锁页播放', () => {
  assert.ok(compose.includes('VoiceRecorderBar'));
  assert.ok(compose.includes('payload.voiceFileName = this.voiceFileName'));
  assert.ok(compose.includes('MediaStore.shared.deleteMedia(payload.voiceFileName)'));
  assert.ok(vault.includes('embedVoiceIfNeeded(payload)'));
  assert.ok(vault.includes('embeddedVoiceData'));
  assert.ok(unlock.includes('this.payload.voiceFileName'));
  assert.ok(unlock.includes('VoicePlayerBubble'));
});

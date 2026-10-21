import test from 'node:test';
import assert from 'node:assert/strict';
import { PromptPlayer, protectedMediaURL } from '../../server/ai/learning/web/prompt_player.js';
const origin = 'https://family.example';
function harness() {
  const played = [], paused = [];
  const player = new PromptPlayer({ origin, createAudio: url => ({ play: async () => played.push(url), pause: () => paused.push(url), currentTime: 0, addEventListener() {} }) });
  return { player, played, paused };
}
const activity = { kind: 'listen_choice', instruction: 'An introduction must never be spoken', prompt: { audio_url: '/learning/media/question.wav', role: 'question' }, answer: { audio_url: '/learning/media/answer.wav', role: 'answer' } };
test('question plays exactly its prompt URL; never instruction or answer', async () => {
  const {player, played} = harness(); await player.playPrompt(activity);
  assert.deepEqual(played, [origin + activity.prompt.audio_url]);
});
test('answer only plays by explicit example action, and stops current prompt', async () => {
  const {player, played, paused} = harness(); await player.playPrompt(activity); await player.playAnswer(activity);
  assert.deepEqual(played, [origin + activity.prompt.audio_url, origin + activity.answer.audio_url]);
  assert.equal(paused.length, 1);
});
test('missing prompt never falls back to answer or browser speech', async () => {
  const {player, played} = harness(); await assert.rejects(player.playPrompt({...activity, prompt: {role: 'question'}}), /原声/); assert.equal(played.length, 0);
});
test('context narration cannot play as question, song context is explicitly allowed', async () => {
  const {player, played} = harness(); await assert.rejects(player.playPrompt({...activity, prompt: {...activity.prompt, role:'context'}}), /角色/);
  await player.playPrompt({...activity, kind:'music', prompt:{...activity.prompt, role:'context'}}); assert.equal(played.length, 1);
});
test('media refuses external, scheme-relative, data, credentials, traversal and wrong paths', () => {
  for (const url of ['https://evil.example/learning/a', '//evil.example/learning/a', 'data:audio/wav,x', 'https://u:p@family.example/learning/a', '/private/a', '/learning/../private/a', '/learning/%2e%2e/private']) assert.throws(() => protectedMediaURL(url, origin));
  assert.equal(protectedMediaURL('/learning/media/a', origin), origin + '/learning/media/a');
});

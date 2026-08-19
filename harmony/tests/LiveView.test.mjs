import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const activity = await readFile(new URL('../entry/src/main/ets/services/BubuActivityController.ets', import.meta.url), 'utf8');
const recorder = await readFile(new URL('../entry/src/main/ets/services/AudioRecorder.ets', import.meta.url), 'utf8');
const health = await readFile(new URL('../entry/src/main/ets/view/HealthHomeView.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const capsule = await readFile(new URL('../entry/src/main/ets/view/CapsuleComposeView.ets', import.meta.url), 'utf8');

test('录音优先使用原生 TIMER 实况窗，权益不可用时降级常驻通知', () => {
  assert.ok(activity.includes("import { liveViewManager } from '@kit.LiveViewKit'"));
  assert.ok(activity.includes('liveViewManager.isLiveViewEnabled()'));
  assert.ok(activity.includes('liveViewManager.startLiveView'));
  assert.ok(activity.includes('liveViewManager.stopLiveView'));
  assert.ok(activity.includes("event: 'TIMER'"));
  assert.ok(activity.includes('notificationManager.publish'));
  assert.ok(recorder.includes('startVoiceRecording(ServerConfig.shared.childName)'));
  assert.ok(recorder.includes('endVoiceRecording(AudioRecorder.timeText(dur))'));
});

test('手机哄睡计时跨进程持久化并在醒来时自动落睡眠记录', () => {
  assert.ok(config.includes("sleepStartedAt = await this.getNum('sleepStartedAt', 0)"));
  assert.ok(health.includes("Text('开始哄睡计时')"));
  assert.ok(health.includes('startSleepTimer(ServerConfig.shared.childName'));
  assert.ok(health.includes('endSleepTimer(amountText)'));
  assert.ok(health.includes('AppDatabase.shared.insertHealth(record)'));
  assert.ok(health.includes('FeedEventKind.healthRecorded'));
});

test('临近解锁的时间胶囊接同一套原生倒计时实况窗', () => {
  assert.ok(activity.includes('startCapsuleCountdown'));
  assert.ok(activity.includes('remaining > MAX_ALIVE_SECONDS * 1000'));
  assert.ok(capsule.includes('BubuActivityController.shared.startCapsuleCountdown'));
});

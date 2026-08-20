import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const members = await readFile(new URL('../entry/src/main/ets/view/MembersView.ets', import.meta.url), 'utf8');

test('成员删除禁止删最后一人、必须二次确认且保留历史记录说明', () => {
  assert.ok(members.includes('this.memberList().length <= 1'));
  assert.ok(members.includes("title: '要删除这位家人吗？'"));
  assert.ok(members.includes('记录过的内容仍会保留'));
});

test('删除当前身份先切换 fallback 并主动同步', () => {
  assert.ok(members.includes('m.relation === ServerConfig.shared.currentRoleRaw'));
  assert.ok(members.includes('await ServerConfig.shared.setRole(fallback.relation as FamilyRole)'));
  assert.ok(members.includes('SyncEngine.shared.start()'));
});

test('成员支持整行切换身份和编辑且图标动作有无障碍名称', () => {
  assert.ok(members.includes('this.switchTo(m)'));
  assert.ok(members.includes('this.beginEdit(m)'));
  assert.ok(members.includes('editingMember'));
  assert.ok(members.includes('.accessibilityText(`编辑${m.name}`)'));
  assert.ok(members.includes('.accessibilityText(`删除${m.name}`)'));
});

import { util } from '@kit.ArkTS';
import { FamilyMember } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { FamilyRole, SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';

// MARK: - 家庭成员（对照 iOS MembersView）
// 适老化：不设密码，「选择你是谁」。每位成员 emoji 头像 + 关系称谓。
@Component
export struct MembersView {
  @State members: FamilyMember[] = [];
  @State showAdd: boolean = false;
  @State newName: string = '';
  @State relationIndex: number = 0;
  @State emojiIndex: number = 0;
  @State editingMember: FamilyMember | null = null;

  private relations: string[] = ['爸爸', '妈妈', '姥姥', '姥爷', '爷爷', '奶奶', '其他'];
  private emojis: string[] = ['👩', '👨', '👵', '👴', '🧑', '👧'];

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.members = await AppDatabase.shared.fetchMembers() ?? [];
  }

  private memberList(): FamilyMember[] {
    return this.members ?? [];
  }

  build() {
    if (this.showAdd) {
      this.addPanel()
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text('家庭成员').fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Button('+ 添加').backgroundColor(BubuColor.primary)
            .onClick(() => {
              this.editingMember = null;
              this.newName = '';
              this.relationIndex = 0;
              this.emojiIndex = 0;
              this.showAdd = true;
            })
        }.width('100%')

        if (this.memberList().length === 0) {
          Text('把家人都请进来，一起记录布布的成长')
            .fontSize(13).fontColor(BubuColor.secondaryText).margin({ top: 30 })
        } else {
          ForEach(this.memberList(), (m: FamilyMember) => {
            Row({ space: 12 }) {
              Row({ space: 12 }) {
                Text(m.avatarEmoji).fontSize(30)
                Column() {
                  Text(m.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
                  Text(m.relation).fontSize(12).fontColor(BubuColor.secondaryText)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (m.relation === ServerConfig.shared.currentRoleRaw) {
                  Text('当前').fontSize(11).fontColor(Color.White).padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor(BubuColor.primary).borderRadius(10)
                }
              }
              .layoutWeight(1)
              .onClick(() => { this.switchTo(m); })
              .accessibilityText(`切换到${m.name}`)
              Text('✎').fontSize(20).width(44).height(44).textAlign(TextAlign.Center)
                .onClick(() => { this.beginEdit(m); }).accessibilityText(`编辑${m.name}`)
              Text('🗑').fontSize(18).width(44).height(44).textAlign(TextAlign.Center)
                .onClick(() => { this.requestRemove(m); }).accessibilityText(`删除${m.name}`)
            }
            .width('100%').padding(14)
            .backgroundColor(BubuColor.card).borderRadius(14)
          }, (m: FamilyMember) => m.id)
        }
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  @Builder
  addPanel() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showAdd = false; })
        Text(this.editingMember === null ? '添加家庭成员' : '编辑家庭成员')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')
      TextInput({ text: $$this.newName, placeholder: '名字，如「王芳」或「妈妈」' })
        .height(48).backgroundColor('#F3F3F3').borderRadius(10)
      Row() {
        Text('关系').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        Select(this.relations.map((r): SelectOption => ({ value: r })))
          .selected(this.relationIndex).value(this.relations[this.relationIndex])
          .onSelect((i: number) => { this.relationIndex = i; })
      }.width('100%')
      Row({ space: 8 }) {
        ForEach(this.emojis, (e: string, i: number) => {
          Text(e).fontSize(28)
            .padding(6).borderRadius(10)
            .backgroundColor(this.emojiIndex === i ? '#FFE5EA' : Color.Transparent)
            .onClick(() => { this.emojiIndex = i; })
        }, (e: string) => e)
      }
      Button('保存').width('100%').backgroundColor(BubuColor.primary)
        .onClick(() => { this.save(); })
    }
    .padding(20).width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  private async save(): Promise<void> {
    const now = Date.now();
    const existing = this.editingMember;
    const oldRelation = existing?.relation;
    const m: FamilyMember = {
      id: existing?.id ?? util.generateRandomUUID(true),
      remoteId: existing?.remoteId,
      name: this.newName.trim().length === 0 ? this.relations[this.relationIndex] : this.newName.trim(),
      relation: this.relations[this.relationIndex],
      avatarEmoji: this.emojis[this.emojiIndex],
      themeColorHex: '#F28C9E',
      isPrimary: existing?.isPrimary ?? this.memberList().length === 0,
      syncState: SyncState.local,
      createdAt: existing?.createdAt ?? now
    };
    await AppDatabase.shared.upsertMember(m);
    if (oldRelation === ServerConfig.shared.currentRoleRaw) {
      await ServerConfig.shared.setRole(m.relation as FamilyRole);
    }
    this.editingMember = null;
    this.showAdd = false;
    await this.reload();
    SyncEngine.shared.start();
    this.getUIContext().getPromptAction().showToast({ message: existing ? '已更新 💛' : '已添加 💛' });
  }

  private beginEdit(member: FamilyMember): void {
    this.editingMember = member;
    this.newName = member.name;
    const relation = this.relations.indexOf(member.relation);
    this.relationIndex = relation >= 0 ? relation : this.relations.length - 1;
    const emoji = this.emojis.indexOf(member.avatarEmoji);
    this.emojiIndex = emoji >= 0 ? emoji : 0;
    this.showAdd = true;
  }

  private async switchTo(member: FamilyMember): Promise<void> {
    await ServerConfig.shared.setRole(member.relation as FamilyRole);
    this.getUIContext().getPromptAction().showToast({ message: `现在由${member.name}记录` });
  }

  private requestRemove(member: FamilyMember): void {
    if (this.memberList().length <= 1) {
      this.getUIContext().getPromptAction().showToast({ message: '至少要留一位家人，请先添加新成员' });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '要删除这位家人吗？',
      message: `「${member.name}」会从全家设备移除，TA 记录过的内容仍会保留。`,
      primaryButton: { value: `删除「${member.name}」`, fontColor: BubuColor.danger, action: () => { this.remove(member); } },
      secondaryButton: { value: '再想想', action: () => {} }
    });
  }

  private async remove(m: FamilyMember): Promise<void> {
    if (this.memberList().length <= 1) return;
    if (m.relation === ServerConfig.shared.currentRoleRaw) {
      const fallback = this.memberList().find((item: FamilyMember): boolean => item.id !== m.id);
      if (fallback) await ServerConfig.shared.setRole(fallback.relation as FamilyRole);
    }
    await AppDatabase.shared.enqueueRemoteDeletion('members', m.remoteId);
    await AppDatabase.shared.deleteMember(m.id);
    await this.reload();
    SyncEngine.shared.start();
  }
}

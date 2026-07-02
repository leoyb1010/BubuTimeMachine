import { util } from '@kit.ArkTS';
import { FamilyMember } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// MARK: - 家庭成员（对照 iOS MembersView）
// 适老化：不设密码，「选择你是谁」。每位成员 emoji 头像 + 关系称谓。
@Component
export struct MembersView {
  @State members: FamilyMember[] = [];
  @State showAdd: boolean = false;
  @State newName: string = '';
  @State relationIndex: number = 0;
  @State emojiIndex: number = 0;

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
              Text(m.avatarEmoji).fontSize(30)
              Column() {
                Text(m.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
                Text(m.relation).fontSize(12).fontColor(BubuColor.secondaryText)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Text('🗑').fontSize(18).onClick(() => { this.remove(m); })
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
        Text('添加家庭成员')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')
      Text('添加家庭成员').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
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
    const m: FamilyMember = {
      id: util.generateRandomUUID(true),
      name: this.newName.trim().length === 0 ? this.relations[this.relationIndex] : this.newName.trim(),
      relation: this.relations[this.relationIndex],
      avatarEmoji: this.emojis[this.emojiIndex],
      themeColorHex: '#F28C9E',
      isPrimary: this.memberList().length === 0,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.upsertMember(m);
    this.showAdd = false;
    await this.reload();
    promptAction.showToast({ message: '已添加 💛' });
  }

  private async remove(m: FamilyMember): Promise<void> {
    await AppDatabase.shared.enqueueRemoteDeletion('members', m.remoteId);
    await AppDatabase.shared.deleteMember(m.id);
    await this.reload();
  }
}

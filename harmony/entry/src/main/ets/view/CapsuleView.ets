import { util } from '@kit.ArkTS';
import { TimeCapsule } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { ServerConfig } from '../services/ServerConfig';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// MARK: - 时间胶囊（对照 iOS CapsuleHomeView）
// 写给未来布布的信，设解锁日期；未到期锁定，到期可开启。
@Component
export struct CapsuleView {
  @State capsules: TimeCapsule[] = [];
  @State showCompose: boolean = false;
  @State draftTitle: string = '';
  @State draftLetter: string = '';
  @State unlockMs: number = Date.now() + 365 * 86400000; // 默认一年后

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.capsules = await AppDatabase.shared.fetchCapsules();
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('时间胶囊').fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Button('写一封').backgroundColor(BubuColor.primary)
            .onClick(() => {
              this.draftTitle = '';
              this.draftLetter = '';
              this.unlockMs = Date.now() + 365 * 86400000;
              this.showCompose = true;
            })
        }.width('100%')

        if (this.capsules.length === 0) {
          Column({ space: 10 }) {
            Text('✉️').fontSize(56)
            Text('写给未来布布的第一封信').fontSize(15).fontColor(BubuColor.warmBrown)
            Text('设一个解锁日，到那天再打开').fontSize(12).fontColor(BubuColor.secondaryText)
          }.width('100%').padding({ top: 40 })
        } else {
          ForEach(this.capsules, (c: TimeCapsule) => {
            this.capsuleCard(c)
          }, (c: TimeCapsule) => c.id)
        }
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
    .bindSheet($$this.showCompose, this.composeSheet(), { height: 420 })
  }

  private isLocked(c: TimeCapsule): boolean {
    return c.unlockAt > Date.now();
  }

  @Builder
  capsuleCard(c: TimeCapsule) {
    Row({ space: 12 }) {
      Text(c.coverEmoji ?? (this.isLocked(c) ? '🔒' : '✉️')).fontSize(32)
      Column() {
        Text(c.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        Text(`来自${c.fromRole}`).fontSize(11).fontColor(BubuColor.secondaryText)
        Text(this.isLocked(c) ? `${this.daysLeft(c.unlockAt)} 天后解锁` : '已可开启')
          .fontSize(12).fontColor(this.isLocked(c) ? BubuColor.secondaryText : BubuColor.success)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (!this.isLocked(c)) {
        Text('开启 ▶').fontSize(13).fontColor(BubuColor.primary)
      }
    }
    .width('100%').padding(14)
    .backgroundColor(BubuColor.card).borderRadius(16)
    .opacity(this.isLocked(c) ? 0.9 : 1)
  }

  @Builder
  composeSheet() {
    Column({ space: 14 }) {
      Text('写给未来布布').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      TextInput({ text: $$this.draftTitle, placeholder: '给这封信起个名字' })
        .height(48).backgroundColor('#F3F3F3').borderRadius(10)
      TextArea({ text: $$this.draftLetter, placeholder: '想对长大的布布说点什么…' })
        .height(140).backgroundColor('#F3F3F3').borderRadius(10)
      Row() {
        Text('解锁日').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        Button(this.dateText(this.unlockMs)).backgroundColor(Color.Transparent).fontColor(BubuColor.primary)
          .onClick(() => {
            DatePickerDialog.show({
              selected: new Date(this.unlockMs),
              onDateAccept: (d: Date) => { this.unlockMs = d.getTime(); }
            });
          })
      }.width('100%')
      Button('封存').width('100%').backgroundColor(BubuColor.primary)
        .onClick(() => { this.save(); })
    }
    .padding(20).width('100%')
  }

  private async save(): Promise<void> {
    const title = this.draftTitle.trim().length === 0 ? '给未来布布的信' : this.draftTitle.trim();
    const now = Date.now();
    const c: TimeCapsule = {
      id: util.generateRandomUUID(true),
      title: title,
      fromRole: ServerConfig.shared.currentRole,
      unlockAt: this.unlockMs,
      isLocked: true,
      coverEmoji: '💌',
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertCapsule(c);
    this.showCompose = false;
    await this.reload();
    promptAction.showToast({ message: '已经封存啦 💌' });
  }

  private daysLeft(ms: number): number {
    return Math.max(0, Math.ceil((ms - Date.now()) / 86400000));
  }
  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}

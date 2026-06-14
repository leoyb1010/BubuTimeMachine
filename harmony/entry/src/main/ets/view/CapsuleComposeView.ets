import { util } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { TimeCapsule, ChildProfile } from '../models/Models';
import { SyncState } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { CapsuleCrypto } from '../services/security/CapsuleCrypto';
import { CapsuleVault, CapsulePayload, makeCapsulePayload } from '../services/security/CapsuleVault';
import { CapsuleRecovery } from '../services/security/CapsuleRecovery';
import { BubuColor, BubuFont, BubuRadius, BubuSpacing, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';

// MARK: - 时间胶囊 · 写信（对照 iOS Features/Capsule/CapsuleComposeView.swift）
// 写文字 + 选解锁时间（提供「明年今天」「N岁生日」等快捷项）。
// 保存时用家庭恢复码 v3 真 E2E 加密落盘，UI 立刻锁定。
// NOTE: iOS 还支持录语音（VoiceRecorderBar/VoicePlayerBubble），本切片未携带录音组件，
//       故省略语音段，仅保留文字信；payload 的语音字段保持空（与同步格式兼容）。

// 解锁时间快捷项（对照 iOS quickOptions）。
interface QuickOption {
  label: string;
  dateMs: number;
}

@Component
export struct CapsuleComposeView {
  // 由 CapsuleView 传入：编辑既有胶囊则非空。
  editing: TimeCapsule | null = null;
  // 返回（对照 iOS dismiss）。
  onBack: () => void = () => {};
  // 封存成功回调（让父页刷新列表）。
  onSaved: () => void = () => {};

  @State private title: string = '';
  @State private emoji: string = '💌';
  @State private letter: string = '';
  @State private unlockMs: number = CapsuleComposeView.oneYearFromNow();
  @State private saving: boolean = false;
  @State private profile: ChildProfile | null = null;
  @State private loaded: boolean = false;

  private readonly emojiChoices: string[] = ['💌', '🎁', '🌟', '🎂', '🧸', '🌷', '📮', '🕰️', '💝', '🍼'];

  private static oneYearFromNow(): number {
    const d = new Date();
    d.setFullYear(d.getFullYear() + 1);
    return d.getTime();
  }

  aboutToAppear(): void {
    this.loadEditing();
    this.loadProfile();
  }

  private async loadProfile(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
  }

  // 进入编辑：回填标题/封面/解锁日；到期胶囊回填正文（解密）。对照 iOS loadEditing()。
  private async loadEditing(): Promise<void> {
    if (this.loaded) return;
    this.loaded = true;
    const e = this.editing;
    if (e === null) return;
    this.title = e.title;
    this.emoji = e.coverEmoji ?? '💌';
    this.unlockMs = Math.max(e.unlockAt, Date.now());
    const blob = e.encryptedBlobFileName;
    if (blob && blob.length > 0 && e.unlockAt <= Date.now()) {
      try {
        const recovery = CapsuleRecovery.current();
        const payload = await CapsuleVault.shared.unseal(
          blob, e.unlockAt, e.id, recovery ?? undefined);
        this.letter = payload.letter;
      } catch (err) {
        // 解不开就保留空正文（与 iOS try? 一致）。
      }
    }
  }

  build() {
    Column() {
      // 顶栏：返回 + 标题 + 封存（对照 iOS toolbar cancellation/confirmation）。
      Row({ space: 12 }) {
        Button('取消')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.onBack(); })
        Text(this.editing === null ? '写给未来的布布' : '修改时间胶囊')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('封存')
          .backgroundColor(this.canSave() && !this.saving ? BubuColor.primary : BubuColor.softFill)
          .fontColor(this.canSave() && !this.saving ? '#FFFFFF' : BubuColor.secondaryText)
          .enabled(this.canSave() && !this.saving)
          .onClick(() => { this.save(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: BubuSpacing.section }) {
          this.emojiPicker()
          this.titleField()
          this.letterField()
          this.unlockSection()
          Blank().height(20)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  // 封面 emoji 横向选择器（对照 iOS emojiPicker）。
  @Builder
  emojiPicker() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.emojiChoices, (e: string) => {
          Text(e)
            .fontSize(30)
            .width(50)
            .height(50)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.emoji === e ? '#2EF28C9E' : BubuColor.softFill)
            .borderRadius(25)
            .border({ width: this.emoji === e ? 2 : 0, color: this.emoji === e ? BubuColor.primary : Color.Transparent })
            .onClick(() => { this.emoji = e; })
        }, (e: string) => e)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  // 标题输入（对照 iOS titleField）。
  @Builder
  titleField() {
    Column({ space: 8 }) {
      Text('给这封信起个名字').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
      TextInput({ text: $$this.title, placeholder: '如：写给18岁的你' })
        .fontSize(BubuFont.headline)
        .fontColor(BubuColor.warmBrown)
        .height(52)
        .padding({ left: 14, right: 14 })
        .backgroundColor('#B3FFFFFF')
        .borderRadius(BubuRadius.small)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 信件正文（对照 iOS letterField）。
  @Builder
  letterField() {
    Column({ space: 8 }) {
      Text('想对她说的话').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
      TextArea({ text: $$this.letter, placeholder: '亲爱的布布……' })
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.warmBrown)
        .height(180)
        .padding(14)
        .backgroundColor('#B3FFFFFF')
        .borderRadius(BubuRadius.small)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 解锁时间段：快捷 chips + 精确日期（对照 iOS unlockSection）。
  @Builder
  unlockSection() {
    Column({ space: 12 }) {
      Text('什么时候可以打开').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.quickOptions(), (opt: QuickOption) => {
            Text(opt.label)
              .fontSize(BubuFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSelected(opt.dateMs) ? '#FFFFFF' : BubuColor.warmBrown)
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .backgroundColor(this.isSelected(opt.dateMs) ? BubuColor.primary : BubuColor.softFill)
              .borderRadius(20)
              .onClick(() => {
                if (this.canRewritePayload()) { this.unlockMs = opt.dateMs; }
              })
          }, (opt: QuickOption) => opt.label)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // 精确到天：点开 DatePickerDialog（对照 iOS DatePicker .date）。
      Row() {
        Text('精确到天').fontSize(BubuFont.body).fontColor(BubuColor.warmBrown)
        Blank()
        Button(BubuDateFormat.longDate(new Date(this.unlockMs)))
          .backgroundColor(Color.Transparent)
          .fontColor(BubuColor.primary)
          .enabled(this.canRewritePayload())
          .onClick(() => {
            DatePickerDialog.show({
              selected: new Date(this.unlockMs),
              start: new Date(),
              onDateAccept: (d: Date) => { this.unlockMs = d.getTime(); }
            });
          })
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#B3FFFFFF')
      .borderRadius(BubuRadius.small)

      Text(this.editing !== null && !this.canRewritePayload()
        ? '未到期的胶囊只能改标题和封面；内容与解锁日保持封存。'
        : `封存后，到 ${BubuDateFormat.longDate(new Date(this.unlockMs))} 之前都打不开。`)
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.primary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 快捷选项：明年今天 + 6/12/18 岁生日（对照 iOS quickOptions）。
  private quickOptions(): QuickOption[] {
    const opts: QuickOption[] = [];
    const nextYear = new Date();
    nextYear.setFullYear(nextYear.getFullYear() + 1);
    opts.push({ label: '明年今天', dateMs: nextYear.getTime() });
    const p = this.profile;
    if (p !== null) {
      const ages: number[] = [6, 12, 18];
      for (const age of ages) {
        const d = new Date(p.birthday);
        d.setFullYear(d.getFullYear() + age);
        if (d.getTime() > Date.now()) {
          opts.push({ label: `${age}岁生日`, dateMs: d.getTime() });
        }
      }
    }
    return opts;
  }

  private isSelected(dateMs: number): boolean {
    const a = new Date(dateMs);
    const b = new Date(this.unlockMs);
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }

  // 可保存：标题非空 + （编辑态 或 正文非空）。对照 iOS canSave。
  private canSave(): boolean {
    const hasTitle = this.title.trim().length > 0;
    const hasBody = this.letter.trim().length > 0;
    return hasTitle && (this.editing !== null || hasBody);
  }

  // 未到期的编辑只能改标题/封面，不能改内容与解锁日。对照 iOS canRewritePayload。
  private canRewritePayload(): boolean {
    return this.editing === null || this.editing.unlockAt <= Date.now();
  }

  // 封存：v3 真 E2E 加密落盘（对照 iOS save()）。
  private async save(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const sealedUnlockMs = CapsuleCrypto.normalizedMs(this.unlockMs);
      const now = Date.now();
      const e = this.editing;

      // 未到期编辑：只改标题/封面，保持封存。
      if (e !== null && !this.canRewritePayload()) {
        const updated: TimeCapsule = {
          id: e.id, remoteId: e.remoteId, title: this.title.trim(), letterText: e.letterText,
          fromRole: e.fromRole, unlockAt: e.unlockAt, isLocked: e.isLocked,
          encryptedBlobFileName: e.encryptedBlobFileName, coverEmoji: this.emoji,
          syncState: SyncState.local, createdAt: e.createdAt
        };
        await AppDatabase.shared.insertCapsule(updated);
        this.onSaved();
        this.onBack();
        return;
      }

      const id = e !== null ? e.id : util.generateRandomUUID(true);
      const payload: CapsulePayload = makeCapsulePayload(this.letter);

      // v3 真 E2E：用家庭恢复码派生密钥加密，salt 用胶囊 id。
      const recoveryCode = CapsuleRecovery.currentOrCreate();
      const blobName = await CapsuleVault.shared.sealV3(payload, recoveryCode, id);

      const capsule: TimeCapsule = {
        id: id,
        remoteId: e !== null ? e.remoteId : undefined,
        title: this.title.trim(),
        letterText: undefined, // v3：明文不落库，只存加密 blob。
        fromRole: e !== null ? e.fromRole : ServerConfig.shared.currentRole,
        unlockAt: sealedUnlockMs,
        isLocked: true,
        encryptedBlobFileName: blobName,
        coverEmoji: this.emoji,
        syncState: SyncState.local,
        createdAt: e !== null ? e.createdAt : now
      };
      await AppDatabase.shared.insertCapsule(capsule);
      promptAction.showToast({ message: '已经封存啦 💌' });
      this.onSaved();
      this.onBack();
    } catch (err) {
      const e = err as Error;
      promptAction.showDialog({
        title: '封存失败',
        message: `这封信还没有封存成功：${e.message ?? '未知错误'}。可以稍后再试。`,
        buttons: [{ text: '好', color: BubuColor.primary }]
      });
    } finally {
      this.saving = false;
    }
  }
}

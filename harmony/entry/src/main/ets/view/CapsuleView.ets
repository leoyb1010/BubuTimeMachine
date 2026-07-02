import { promptAction } from '@kit.ArkUI';
import { TimeCapsule } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuFont, BubuRadius, BubuSpacing, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';
import { CapsuleComposeView } from './CapsuleComposeView';
import { CapsuleUnlockView } from './CapsuleUnlockView';
import { CapsuleRecoveryView } from './CapsuleRecoveryView';

// MARK: - 时间胶囊 · 列表（对照 iOS Features/Capsule/CapsuleHomeView.swift）
// 写给未来布布的信，到期前加密锁定、只显示倒计时；到期后可庄重开启。
// RootPage 以 Tab 渲染本页（无 NavStack），内部用 route 状态切换子页，子页带 onBack 返回。
// NOTE: iOS 用 TimelineView 每分钟刷新倒计时 + 呼吸发光；本切片用 setInterval 每分钟刷新倒计时文案。

type CapsuleRoute = 'home' | 'compose' | 'unlock' | 'recovery';

@Component
export struct CapsuleView {
  @State private capsules: TimeCapsule[] = [];
  @State private route: CapsuleRoute = 'home';
  @State private editing: TimeCapsule | null = null;
  @State private unlocking: TimeCapsule | null = null;
  // 每分钟自增以驱动倒计时文案刷新（对照 iOS TimelineView periodic 60s）。
  @State private tick: number = 0;

  private timerId: number = -1;

  aboutToAppear(): void {
    this.reload();
    this.timerId = setInterval(() => { this.tick = this.tick + 1; }, 60000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  private async reload(): Promise<void> {
    this.capsules = await AppDatabase.shared.fetchCapsules() ?? [];
  }

  private canOpen(c: TimeCapsule): boolean {
    return Date.now() >= c.unlockAt;
  }

  private openable(): TimeCapsule[] {
    return this.capsules.filter((c: TimeCapsule): boolean => this.canOpen(c));
  }

  private locked(): TimeCapsule[] {
    return this.capsules.filter((c: TimeCapsule): boolean => !this.canOpen(c));
  }

  build() {
    if (this.route === 'compose') {
      CapsuleComposeView({
        editing: this.editing,
        onBack: () => { this.editing = null; this.route = 'home'; },
        onSaved: () => { this.reload(); }
      })
    } else if (this.route === 'unlock') {
      CapsuleUnlockView({
        capsule: this.unlocking ?? this.capsules[0],
        onBack: () => { this.unlocking = null; this.route = 'home'; },
        onOpened: () => { this.reload(); }
      })
    } else if (this.route === 'recovery') {
      CapsuleRecoveryView({
        onBack: () => { this.route = 'home'; }
      })
    } else {
      this.homePage()
    }
  }

  @Builder
  homePage() {
    Column() {
      // 顶栏：标题 + 恢复码 + 写一封（对照 iOS navigationTitle + toolbar）。
      Row({ space: 12 }) {
        Text('时间胶囊')
          .fontSize(BubuFont.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .layoutWeight(1)
        Text('🔑')
          .fontSize(22)
          .width(40).height(40).textAlign(TextAlign.Center)
          .backgroundColor('#1AF28C9E').borderRadius(20)
          .onClick(() => { this.route = 'recovery'; })
        Text('✍️')
          .fontSize(22)
          .width(40).height(40).textAlign(TextAlign.Center)
          .backgroundColor('#1AF28C9E').borderRadius(20)
          .onClick(() => { this.editing = null; this.route = 'compose'; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.capsules.length === 0) {
        this.emptyState()
      } else {
        Scroll() {
          Column({ space: BubuSpacing.section }) {
            this.intro()
            if (this.openable().length > 0) { this.openableSection() }
            if (this.locked().length > 0) { this.lockedSection() }
            Blank().height(40)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  @Builder
  intro() {
    Text('把此刻的心里话，封存给某个未来的日子。到那天之前，谁也打不开。')
      .fontSize(BubuFont.body)
      .fontColor(BubuColor.secondaryText)
      .width('100%')
  }

  @Builder
  openableSection() {
    Column({ space: 12 }) {
      Text('📬 可以开启了')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.primary)
      ForEach(this.openable(), (c: TimeCapsule) => {
        this.capsuleCard(c, true)
      }, (c: TimeCapsule) => c.id)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  lockedSection() {
    Column({ space: 12 }) {
      Text('🔒 静静等待')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      ForEach(this.locked(), (c: TimeCapsule) => {
        this.capsuleCard(c, false)
      }, (c: TimeCapsule) => c.id)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 单封胶囊卡片（对照 iOS capsuleCard）。tick 入参强制重算倒计时。
  @Builder
  capsuleCard(c: TimeCapsule, open: boolean) {
    Row({ space: 16 }) {
      Text(c.coverEmoji ?? '💌')
        .fontSize(40)
        .width(60).height(60)
        .textAlign(TextAlign.Center)
        .backgroundColor(open ? '#1FF28C9E' : '#1FA98D82')
        .borderRadius(30)
      Column({ space: 4 }) {
        Text(c.title)
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`来自${c.fromRole}`)
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
        if (open) {
          Text('👆 轻触庄重开启')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
        } else {
          Text(this.countdownText(c.unlockAt))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(open ? '›' : (this.isImminent(c) ? '🔓' : '🔒'))
        .fontSize(open ? 24 : 18)
        .fontColor(this.isImminent(c) ? BubuColor.primary : BubuColor.secondaryText)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({
      radius: this.isImminent(c) ? 16 : 12,
      color: this.isImminent(c) ? '#73F28C9E' : '#1A000000',
      offsetY: 4
    })
    .opacity(open ? 1 : 0.96)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      if (open) {
        this.unlocking = c;
        this.route = 'unlock';
      } else {
        promptAction.showDialog({
          title: '还没到解锁日',
          message: this.countdownText(c.unlockAt),
          buttons: [{ text: '知道了', color: BubuColor.primary }]
        });
      }
    })
    // 长按操作：修改 / 删除（对照 iOS contextMenu + swipeActions）。
    .bindContextMenu(this.cardMenu(c), ResponseType.LongPress)
  }

  @Builder
  cardMenu(c: TimeCapsule) {
    Menu() {
      MenuItem({ content: '修改', startIcon: undefined })
        .onClick(() => { this.editing = c; this.route = 'compose'; })
      MenuItem({ content: '删除', startIcon: undefined })
        .onClick(() => { this.confirmDelete(c); })
    }
  }

  @Builder
  emptyState() {
    Column({ space: 18 }) {
      BubuMascotBadge({ badgeSize: 84, expression: BubuExpression.love })
      Text('还没有时间胶囊')
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text('写第一封信，给 18 岁的布布，\n或是给明年今天的她。')
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
      Text('✍️ 写一封')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding({ left: 28, right: 28, top: 14, bottom: 14 })
        .backgroundColor(BubuColor.primary)
        .borderRadius(28)
        .shadow({ radius: BubuShadow.buttonRadius, color: BubuShadow.buttonColor, offsetY: BubuShadow.buttonOffsetY })
        .onClick(() => { this.editing = null; this.route = 'compose'; })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(40)
  }

  // 最后 24 小时进入「即将开启」（对照 iOS imminent）。
  private isImminent(c: TimeCapsule): boolean {
    return !this.canOpen(c) && (c.unlockAt - Date.now()) < 86400000;
  }

  // 倒计时文案（对照 iOS countdownText）。tick 触发重算。
  private countdownText(unlockMs: number): string {
    const now = Date.now();
    const days = Math.floor((unlockMs - now) / 86400000);
    if (days > 365) {
      const years = Math.floor(days / 365);
      return `还要等 ${years} 年 · ${BubuDateFormat.yearMonthDay(new Date(unlockMs))}`;
    }
    if (days > 0) { return `还有 ${days} 天解锁`; }
    const hours = Math.max(0, Math.floor((unlockMs - now) / 3600000));
    if (hours > 0) { return `还有 ${hours} 小时就能打开啦`; }
    return '马上就能开啦';
  }

  private confirmDelete(c: TimeCapsule): void {
    promptAction.showDialog({
      title: '删除时间胶囊',
      message: `确定删除「${c.title}」吗？这封信将无法恢复。`,
      buttons: [
        { text: '取消', color: BubuColor.secondaryText },
        { text: '删除', color: BubuColor.danger }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) { this.deleteCapsule(c); }
    });
  }

  private async deleteCapsule(c: TimeCapsule): Promise<void> {
    await AppDatabase.shared.enqueueRemoteDeletion('timecapsules', c.remoteId);
    await AppDatabase.shared.deleteCapsule(c.id);
    await this.reload();
    promptAction.showToast({ message: '已删除' });
  }
}

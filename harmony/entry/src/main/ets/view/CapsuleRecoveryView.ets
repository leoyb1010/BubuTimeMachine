import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { CapsuleRecovery } from '../services/security/CapsuleRecovery';
import { BubuColor, BubuFont, BubuRadius, BubuSpacing, BubuShadow } from '../theme/BubuTheme';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';

// MARK: - 时间胶囊恢复码（对照 iOS Features/Capsule/CapsuleRecoveryView.swift）
// 展示家庭恢复码（v3 真 E2E 的钥匙），引导打印/抄写收进实体盒子；
// 支持用纸条恢复码恢复（换新机 / 钥匙串丢失）。
// NOTE: iOS 用 ShareLink 打印/分享；HarmonyOS 这里用复制到剪贴板等价（无系统分享组件依赖）。

// 带序号的词（LazyForEach 友好）。
interface NumberedWord {
  index: number;
  word: string;
}

@Component
export struct CapsuleRecoveryView {
  onBack: () => void = () => {};

  @State private code: string = '';
  @State private restoring: boolean = false;
  @State private restoreInput: string = '';
  @State private copied: boolean = false;

  aboutToAppear(): void {
    this.code = CapsuleRecovery.current() ?? '';
  }

  private theme(): string { return BubuColor.primary; }

  build() {
    Column() {
      // 顶栏：完成（对照 iOS toolbar confirmation）。
      Row({ space: 12 }) {
        Text('胶囊恢复码')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .layoutWeight(1)
        Button('完成')
          .backgroundColor(BubuColor.primary)
          .fontColor('#FFFFFF')
          .onClick(() => { this.onBack(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: BubuSpacing.section }) {
          this.intro()
          this.codeCard()
          if (this.code.length > 0) { this.actions() }
          this.restoreSection()
          this.warning()
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
    .backgroundColor(BubuColor.background)
  }

  @Builder
  intro() {
    Column({ space: 8 }) {
      Text('🔑 这是布布所有时间胶囊的钥匙')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme())
      Text('时间胶囊用这串恢复码真正加密——服务器即使被攻破，没有它也打不开。它会随你的钥匙串同步到全家的设备。')
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.secondaryText)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  codeCard() {
    if (this.code.length === 0) {
      Column({ space: 12 }) {
        BubuMascotBadge({ badgeSize: 56, expression: BubuExpression.thinking })
        Text('还没有恢复码。写下第一封时间胶囊时会自动生成，也可以现在就生成并抄下来。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .textAlign(TextAlign.Center)
        Text('现在生成')
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .backgroundColor(this.theme())
          .borderRadius(24)
          .onClick(() => {
            this.code = CapsuleRecovery.currentOrCreate();
            promptAction.showToast({ message: '已生成，请务必抄下来 🔑' });
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(BubuColor.card)
      .borderRadius(BubuRadius.card)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    } else {
      Column({ space: 12 }) {
        Text('你的 24 词恢复码')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
        // 三列网格（对照 iOS LazyVGrid count:3）。
        Grid() {
          ForEach(this.numberedWords(), (w: NumberedWord) => {
            GridItem() {
              Text(`${w.index}. ${w.word}`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(BubuColor.warmBrown)
                .width('100%')
                .textAlign(TextAlign.Start)
            }
          }, (w: NumberedWord) => w.index.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .width('100%')
        .height(this.gridHeight())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFDF8')
      .borderRadius(BubuRadius.card)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    }
  }

  @Builder
  actions() {
    Row({ space: 12 }) {
      Text(this.copied ? '已复制 ✓' : '复制')
        .fontSize(BubuFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme())
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 12 })
        .backgroundColor('#1AF28C9E')
        .borderRadius(24)
        .onClick(() => { this.copyCode(); })
    }
    .width('100%')
  }

  @Builder
  restoreSection() {
    Column({ space: 10 }) {
      Text('🔄 用纸条上的恢复码恢复')
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.secondaryText)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseInOut }, () => { this.restoring = !this.restoring; });
        })
      if (this.restoring) {
        TextArea({ text: $$this.restoreInput, placeholder: '把 24 个词按顺序输进来，用空格隔开' })
          .fontSize(15)
          .height(120)
          .padding(14)
          .backgroundColor(BubuColor.card)
          .borderRadius(BubuRadius.small)
        Text('恢复')
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canRestore() ? '#FFFFFF' : BubuColor.secondaryText)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .backgroundColor(this.canRestore() ? this.theme() : BubuColor.softFill)
          .borderRadius(24)
          .onClick(() => {
            if (!this.canRestore()) return;
            CapsuleRecovery.restore(this.restoreInput);
            this.code = CapsuleRecovery.current() ?? '';
            this.restoreInput = '';
            this.restoring = false;
            promptAction.showToast({ message: '恢复码已更新 🔑' });
          })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  warning() {
    Text('务必把这串词抄在纸上，收进家里的盒子。30 年后即使手机、钥匙串都不在了，有这张纸，布布依然能打开你今天写下的信。')
      .fontSize(12)
      .fontColor(BubuColor.danger)
      .width('100%')
  }

  // 至少 12 个词才允许恢复（对照 iOS disabled < 12）。
  private canRestore(): boolean {
    return this.restoreInput.split(/[\s]+/).filter((w: string): boolean => w.length > 0).length >= 12;
  }

  private numberedWords(): NumberedWord[] {
    const words = this.code.split(' ').filter((w: string): boolean => w.length > 0);
    const out: NumberedWord[] = [];
    for (let i = 0; i < words.length; i++) {
      out.push({ index: i + 1, word: words[i] });
    }
    return out;
  }

  // 网格高度估算：每行约 26，三列。
  private gridHeight(): number {
    const count = this.numberedWords().length;
    const rows = Math.ceil(count / 3);
    return rows * 26;
  }

  private copyCode(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
    const sysPasteboard = pasteboard.getSystemPasteboard();
    sysPasteboard.setData(data).then(() => {
      this.copied = true;
      promptAction.showToast({ message: '已复制到剪贴板' });
    });
  }
}

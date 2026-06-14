import { TimeCapsule } from '../models/Models';
import { SyncState } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { CapsuleVault, CapsulePayload } from '../services/security/CapsuleVault';
import { CapsuleCrypto, CapsuleCryptoError } from '../services/security/CapsuleCrypto';
import { CapsuleRecovery } from '../services/security/CapsuleRecovery';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';

// MARK: - 时间胶囊 · 庄重开启（三幕制）（对照 iOS Features/Capsule/CapsuleUnlockView.swift）
// 第一幕「破封」：封蜡碎裂粒子；第二幕「时光回溯」：字幕告诉等了多久；
// 第三幕「信纸展开」：解密内容浮现。全程可点击跳过。
// NOTE: iOS 用触觉/音效/symbolEffect；本切片以无触觉的纯动画 + emoji 等价呈现。
//       语音段省略（无录音组件），只展示文字信。

type UnlockPhase = 'sealed' | 'cracking' | 'retrospect' | 'revealed';

// 破封粒子（对照 iOS 12 个封蜡碎片）。
interface SealShard {
  index: number;
  dx: number;
  dy: number;
  big: boolean;
}

@Component
export struct CapsuleUnlockView {
  capsule: TimeCapsule = CapsuleUnlockView.emptyCapsule();
  onBack: () => void = () => {};
  // 解开后回调（让父页刷新锁定态）。
  onOpened: () => void = () => {};

  @State private phase: UnlockPhase = 'sealed';
  @State private payload: CapsulePayload | null = null;
  @State private errorText: string = '';
  @State private burst: boolean = false;
  @State private skipped: boolean = false;

  private shards: SealShard[] = CapsuleUnlockView.makeShards();

  private static emptyCapsule(): TimeCapsule {
    return {
      id: '', title: '', fromRole: '', unlockAt: 0, isLocked: true,
      syncState: SyncState.local, createdAt: Date.now()
    };
  }

  private static makeShards(): SealShard[] {
    const out: SealShard[] = [];
    for (let i = 0; i < 12; i++) {
      const angle = (i / 12) * 2 * Math.PI;
      out.push({
        index: i,
        dx: Math.cos(angle) * 110,
        dy: Math.sin(angle) * 110,
        big: i % 3 === 0
      });
    }
    return out;
  }

  private theme(): string { return BubuColor.primary; }

  build() {
    Stack() {
      // 主题渐变底（对照 iOS LinearGradient，回溯期更深）。
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.phase === 'retrospect'
            ? [['#F2F28C9E', 0.0], ['#A6F28C9E', 1.0]]
            : [['#D9F28C9E', 0.0], ['#80F28C9E', 1.0]]
        })

      // 各幕内容
      if (this.phase === 'sealed') {
        this.sealedView()
      } else if (this.phase === 'cracking') {
        this.crackingView()
      } else if (this.phase === 'retrospect') {
        this.retrospectView()
      } else {
        this.revealedView()
      }

      // 关闭按钮（右上角）。
      Column() {
        Row() {
          Blank()
          Text('✕')
            .fontSize(26)
            .fontColor('#D9FFFFFF')
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.onBack(); })
        }
        .width('100%')
        Blank()
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .onClick(() => {
      // 典礼可跳过：破封/回溯期间点一下直达信纸。
      if (this.phase === 'cracking' || this.phase === 'retrospect') {
        this.skipped = true;
        this.finishReveal();
      }
    })
  }

  // MARK: 第〇幕 · 封存态
  @Builder
  sealedView() {
    Column({ space: 28 }) {
      Text(this.capsule.coverEmoji ?? '💌')
        .fontSize(100)
        .shadow({ radius: 20, color: '#33000000', offsetY: 10 })
      Column({ space: 8 }) {
        Text(this.capsule.title)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
        Text(`来自${this.capsule.fromRole} · 封存于 ${BubuDateFormat.shortDate(new Date(this.capsule.createdAt))}`)
          .fontSize(BubuFont.caption)
          .fontColor('#D9FFFFFF')
          .textAlign(TextAlign.Center)
      }
      Text('🤚 郑重地打开它')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme())
        .padding({ left: 30, right: 30, top: 15, bottom: 15 })
        .backgroundColor('#FFFFFF')
        .borderRadius(28)
        .onClick(() => { this.open(); })
    }
    .padding(40)
    .justifyContent(FlexAlign.Center)
  }

  // MARK: 第一幕 · 破封（封蜡碎片向四周飞散）
  @Builder
  crackingView() {
    Stack() {
      ForEach(this.shards, (s: SealShard) => {
        Circle()
          .width(s.big ? 10 : 6)
          .height(s.big ? 10 : 6)
          .fill('#E6FFFFFF')
          .translate({ x: this.burst ? s.dx : 0, y: this.burst ? s.dy : 0 })
          .opacity(this.burst ? 0 : 1)
      }, (s: SealShard) => s.index.toString())
      Text(this.capsule.coverEmoji ?? '💌')
        .fontSize(100)
        .scale({ x: this.burst ? 1.18 : 1, y: this.burst ? 1.18 : 1 })
        .rotate({ angle: this.burst ? -4 : 0 })
    }
    .alignContent(Alignment.Center)
    .onAppear(() => {
      animateTo({ duration: 650, curve: Curve.EaseOut }, () => { this.burst = true; });
    })
  }

  // MARK: 第二幕 · 时光回溯
  @Builder
  retrospectView() {
    Column({ space: 18 }) {
      Text('⏳').fontSize(56)
      Text(this.waitedText())
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
      Text('现在，它是你的了')
        .fontSize(BubuFont.body)
        .fontColor('#D9FFFFFF')
    }
    .padding(40)
    .justifyContent(FlexAlign.Center)
  }

  // 「这封信等了你 X 年 X 个月」——封存日到今天（对照 iOS waitedText）。
  private waitedText(): string {
    const from = new Date(this.capsule.createdAt);
    const now = new Date();
    let years = now.getFullYear() - from.getFullYear();
    let months = now.getMonth() - from.getMonth();
    let days = now.getDate() - from.getDate();
    if (days < 0) { months -= 1; }
    if (months < 0) { months += 12; years -= 1; }
    if (years < 0) { years = 0; }
    const totalDays = Math.max(1, Math.floor((now.getTime() - from.getTime()) / 86400000));
    if (years > 0) {
      return months > 0 ? `这封信等了你\n${years} 年 ${months} 个月` : `这封信等了你\n整整 ${years} 年`;
    }
    if (months > 0) {
      const remDays = days < 0 ? 0 : days;
      return `这封信等了你\n${months} 个月 ${remDays} 天`;
    }
    return `这封信等了你\n${totalDays} 天`;
  }

  // MARK: 第三幕 · 信纸展开
  @Builder
  revealedView() {
    if (this.errorText.length > 0) {
      Column({ space: 16 }) {
        BubuMascotBadge({ badgeSize: 72, expression: BubuExpression.shy })
        Text(this.errorText)
          .fontSize(BubuFont.body)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
      }
      .padding(40)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 6 }) {
            Text(this.capsule.coverEmoji ?? '💌').fontSize(50)
            Text(this.capsule.title)
              .fontSize(BubuFont.title)
              .fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown)
          }
          .width('100%')

          if (this.payload !== null && this.payload.letter.length > 0) {
            Text(this.payload.letter)
              .fontSize(19)
              .fontColor(BubuColor.warmBrown)
              .lineHeight(30)
              .width('100%')
          }

          Text(`—— 来自${this.capsule.fromRole}，写于 ${BubuDateFormat.longDate(new Date(this.capsule.createdAt))}`)
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
            .textAlign(TextAlign.End)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(26)
        .margin({ left: 16, right: 16, top: 56, bottom: 16 })
        .backgroundColor('#FFFDF8')
        .borderRadius(BubuRadius.card)
      }
      .width('100%')
      .height('100%')
    }
  }

  // MARK: 典礼编排（对照 iOS open / finishReveal）
  private async open(): Promise<void> {
    // 先解密（本地、毫秒级），典礼只是给结果一个庄重的入场。
    await this.decrypt();

    // 破封 → 回溯 → 信纸；任一阶段被点击跳过则直达信纸。
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.phase = 'cracking'; });
    setTimeout(() => {
      if (this.skipped) return;
      animateTo({ duration: 400, curve: Curve.Smooth }, () => { this.phase = 'retrospect'; });
      setTimeout(() => {
        if (this.skipped) return;
        this.finishReveal();
      }, 1500);
    }, 750);
  }

  private finishReveal(): void {
    animateTo({ duration: 500, curve: Curve.Smooth }, () => { this.phase = 'revealed'; });
  }

  // 解密内容并解除锁定（对照 iOS decrypt）。
  private async decrypt(): Promise<void> {
    const blob = this.capsule.encryptedBlobFileName;
    if (!blob || blob.length === 0) {
      // 兼容旧数据：若有明文 letterText 则直接展示。
      if (this.capsule.letterText && this.capsule.letterText.length > 0) {
        this.payload = { letter: this.capsule.letterText, voiceDuration: 0, voiceWaveform: [], photoFileNames: [] };
        await this.markOpened();
        return;
      }
      this.errorText = '这封胶囊的加密内容还没同步到本机，请先回到设置里点一次立即同步。';
      return;
    }
    try {
      const recovery = CapsuleRecovery.current();
      const p = await CapsuleVault.shared.unseal(
        blob, this.capsule.unlockAt, this.capsule.id, recovery ?? undefined);
      this.payload = p;
      await this.markOpened();
    } catch (err) {
      const e = err as CapsuleCryptoError;
      // v3 需要恢复码却没有：给出引导文案（对照 iOS）。
      if (e instanceof CapsuleCryptoError && e.kind === 'decryptionFailed' && CapsuleRecovery.current() === null) {
        this.errorText = '这封信是加密的，需要家庭恢复码才能打开。请到「恢复码」里用纸条恢复码恢复。';
      } else {
        this.errorText = e.message ?? '信件打不开了';
      }
    }
  }

  // 标记已开启并落库（对照 iOS isLocked=false + save + syncNow）。
  private async markOpened(): Promise<void> {
    const c = this.capsule;
    const updated: TimeCapsule = {
      id: c.id, remoteId: c.remoteId, title: c.title, letterText: c.letterText,
      fromRole: c.fromRole, unlockAt: c.unlockAt, isLocked: false,
      encryptedBlobFileName: c.encryptedBlobFileName, coverEmoji: c.coverEmoji,
      syncState: SyncState.local, createdAt: c.createdAt
    };
    await AppDatabase.shared.insertCapsule(updated);
    this.onOpened();
  }
}

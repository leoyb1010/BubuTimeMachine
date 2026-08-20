import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine, SyncStatusSnapshot } from '../sync/SyncEngine';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

@Component
export struct SyncCenterView {
  onClose: () => void = () => {};
  onOpenExport: () => void = () => {};

  @State state: string = 'offline';
  @State lastSyncedAt: number = 0;
  @State failureReason: string = '';
  @State nextRetrySeconds: number = 30;
  @State running: boolean = false;
  @State lastExportAtSec: number = 0;

  async aboutToAppear(): Promise<void> {
    this.refresh();
    const context = this.getUIContext().getHostContext() as common.Context;
    const store = await preferences.getPreferences(context, 'bubu_widget');
    const value = await store.get('bubu.lastExportAt', 0);
    this.lastExportAtSec = typeof value === 'number' ? value : 0;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor(BubuColor.softFill)
          .fontColor(BubuColor.warmBrown)
          .onClick(this.onClose)
        Text('同步与备份')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 10 }) {
            Text(this.statusSymbol()).fontSize(42)
            Text(this.statusTitle())
              .fontSize(BubuFont.headline)
              .fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown)
            Text(this.statusDescription())
              .fontSize(BubuFont.caption)
              .fontColor(BubuColor.secondaryText)
              .textAlign(TextAlign.Center)
            if (this.failureReason.length > 0) {
              Text(this.failureReason)
                .fontSize(13)
                .fontColor(BubuColor.danger)
                .padding(10)
                .width('100%')
                .backgroundColor('#14DB3B47')
                .borderRadius(BubuRadius.small)
            }
          }
          .width('100%')
          .padding(22)
          .backgroundColor(BubuColor.card)
          .borderRadius(BubuRadius.card)

          this.backupHealthCard()

          Column({ space: 0 }) {
            this.detailRow('服务器', ServerConfig.shared.isConfigured ? '已配置' : '未登录')
            Divider().color(BubuColor.hairline)
            this.detailRow('连接状态', this.statusTitle())
            Divider().color(BubuColor.hairline)
            this.detailRow('上次同步', this.lastSyncedText())
            Divider().color(BubuColor.hairline)
            this.detailRow('自动重试', `${this.nextRetrySeconds} 秒后检查`)
          }
          .width('100%')
          .backgroundColor(BubuColor.card)
          .borderRadius(BubuRadius.card)

          Button(this.running ? '正在同步…' : '立即同步')
            .width('100%').height(54)
            .backgroundColor(this.running || !ServerConfig.shared.isConfigured ? BubuColor.softFill : BubuColor.primary)
            .fontColor(this.running || !ServerConfig.shared.isConfigured ? BubuColor.secondaryText : Color.White)
            .borderRadius(BubuRadius.button)
            .enabled(!this.running && ServerConfig.shared.isConfigured)
            .onClick(() => { this.syncNow(); })

          Button('重新核对服务器全部内容')
            .width('100%').height(50)
            .backgroundColor(BubuColor.card)
            .fontColor(BubuColor.warmBrown)
            .borderRadius(BubuRadius.button)
            .enabled(!this.running && ServerConfig.shared.isConfigured)
            .onClick(() => { this.pullAll(); })

          Button('本机内容全部重新上传')
            .width('100%').height(50)
            .backgroundColor(BubuColor.card)
            .fontColor(BubuColor.warmBrown)
            .borderRadius(BubuRadius.button)
            .enabled(!this.running && ServerConfig.shared.isConfigured)
            .onClick(() => { this.confirmFullPush(); })

          Text('所有记录先安全保存在本机；断网不会丢，恢复网络后会自动重试。同步只在你自己的服务器和家人设备之间进行。')
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  backupHealthCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(this.exportStale() ? '⚠️' : '🛡️').fontSize(20)
        Text('备份健康度').fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')
      this.detailRow('上次同步', this.lastSyncedText())
      this.detailRow('上次全量存档', this.exportText())
      if (this.exportStale()) {
        Button('现在导出一份完整档案')
          .width('100%').backgroundColor(BubuColor.warning).fontColor(Color.White)
          .onClick(this.onOpenExport)
      }
    }
    .width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  private daysSinceExport(): number {
    if (this.lastExportAtSec <= 0) return -1;
    return Math.floor((Date.now() - this.lastExportAtSec * 1000) / 86400000);
  }

  private exportStale(): boolean {
    const days = this.daysSinceExport();
    return days < 0 || days > 90;
  }

  private exportText(): string {
    const days = this.daysSinceExport();
    if (days < 0) return '从未导出';
    if (days === 0) return '今天';
    return `${days} 天前`;
  }

  @Builder
  private detailRow(title: string, value: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(15).fontColor(BubuColor.secondaryText)
      Blank()
      Text(value).fontSize(15).fontColor(BubuColor.warmBrown).maxLines(2).textAlign(TextAlign.End)
    }
    .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
  }

  private refresh(): void {
    const snapshot: SyncStatusSnapshot = SyncEngine.shared.statusSnapshot();
    this.state = snapshot.state;
    this.running = snapshot.syncing;
    this.lastSyncedAt = snapshot.lastSyncedAt;
    this.failureReason = snapshot.lastFailureReason;
    this.nextRetrySeconds = snapshot.nextRetrySeconds;
  }

  private async syncNow(): Promise<void> {
    if (!ServerConfig.shared.isConfigured || this.running) return;
    this.running = true;
    this.state = 'connecting';
    await SyncEngine.shared.syncNow(true);
    this.refresh();
  }

  private async pullAll(): Promise<void> {
    if (!ServerConfig.shared.isConfigured || this.running) return;
    this.running = true;
    this.state = 'connecting';
    const message = await SyncEngine.shared.pullServerToLocalNow();
    this.running = false;
    if (message.indexOf('失败') >= 0 || message.indexOf('需要') >= 0) {
      this.state = 'offline';
      this.failureReason = message;
    } else {
      this.state = 'online';
      this.lastSyncedAt = Date.now();
      this.failureReason = '';
    }
  }

  private confirmFullPush(): void {
    this.getUIContext().showAlertDialog({
      title: '重新上传本机全部内容？',
      message: '不会删除本机或服务器内容。所有本机记录会重新排队，远端更新版本仍优先保留。',
      primaryButton: { value: '开始重传', action: () => { this.fullPush(); } },
      secondaryButton: { value: '取消', action: () => {} }
    });
  }

  private async fullPush(): Promise<void> {
    if (this.running) return;
    this.running = true;
    const message = await SyncEngine.shared.forceUploadAllLocalData();
    this.running = false;
    this.failureReason = message.indexOf('失败') >= 0 ? message : '';
    this.refresh();
  }

  private statusTitle(): string {
    if (this.running || this.state === 'connecting') return '正在同步';
    if (this.state === 'online') return '已经同步好了';
    return ServerConfig.shared.isConfigured ? '暂时离线' : '还没有登录服务器';
  }

  private statusDescription(): string {
    if (this.running || this.state === 'connecting') return '正在和家里的服务器核对记录…';
    if (this.state === 'online') return '这台设备已经和家里的服务器对齐。';
    return ServerConfig.shared.isConfigured
      ? '连不上也能继续记录，恢复网络后会自动补传。'
      : '不登录也能离线使用；登录后才会同步到其他家人设备。';
  }

  private statusSymbol(): string {
    if (this.running || this.state === 'connecting') return '↻';
    if (this.state === 'online') return '✓';
    return '☁';
  }

  private lastSyncedText(): string {
    return this.lastSyncedAt > 0 ? new Date(this.lastSyncedAt).toLocaleString('zh-CN') : '还没有成功同步';
  }
}

// MARK: - 高级 · 自托管（对照 iOS Features/Settings/AdvancedSettingsView.swift）
// 服务器地址 / 账号密码 / AI 服务 / 连接诊断。普通成员永远不必看见 URL 和密钥——全收进这里。
// iOS 用 Form + Section；ArkUI 用自绘卡片行 + 顶部返回栏（由调用方提供或内置）。

import { ServerConfig } from '../services/ServerConfig';
import { AccountService } from '../services/AccountService';
import { SyncEngine } from '../sync/SyncEngine';
import { ALL_FAMILY_ROLES } from '../models/Enums';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

@Extend(Row)
function advRow() {
  .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
}

@Component
export struct AdvancedSettingsView {
  onClose?: () => void;

  @State baseURL: string = '';
  @State email: string = '';
  @State password: string = '';
  @State aiBaseURL: string = '';
  @State aiAPIKey: string = '';
  @State aiEnabled: boolean = true;
  @State childName: string = '布布';
  @State roleIndex: number = 1; // 默认妈妈
  @State statusText: string = '';

  aboutToAppear(): void {
    const c = ServerConfig.shared;
    this.baseURL = c.baseURLString;
    this.email = c.accountEmail;
    this.password = c.accountPassword;
    this.aiBaseURL = c.aiBaseURLString;
    this.aiAPIKey = c.aiAPIKey;
    this.aiEnabled = c.aiEnabled;
    this.childName = c.childName;
    this.roleIndex = Math.max(0, ALL_FAMILY_ROLES.indexOf(c.currentRole));
  }

  build() {
    Column() {
      if (this.onClose) {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3')
            .fontColor(BubuColor.warmBrown)
            .onClick(() => { this.onClose!(); })
          Text('服务器与 AI 配置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }

      Scroll() {
        Column({ space: 14 }) {
          // —— 连接诊断 ——
          Text('连接诊断').fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
          Row() {
            Text('当前状态').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Text(ServerConfig.shared.isConfigured ? '已配置' : '离线（本地可用）')
              .fontSize(14).fontColor(BubuColor.primary)
          }.advRow()
          Button('立即同步')
            .width('100%').backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
            .enabled(ServerConfig.shared.isConfigured)
            .onClick(() => { SyncEngine.shared.start(); promptAction.showToast({ message: '正在同步…' }); })

          // —— 家里的服务器 ——
          Text('家里的服务器（多设备同步）').fontSize(13).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
          Row() {
            Text('地址').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.baseURL, placeholder: ServerConfig.baseURLPlaceholder })
              .layoutWeight(1).textAlign(TextAlign.End)
          }.advRow()
          Row() {
            Text('家庭账户邮箱/用户名').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.email, placeholder: 'username@bubu.family' })
              .layoutWeight(1).textAlign(TextAlign.End)
          }.advRow()
          Row() {
            Text('账户密码').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.password, placeholder: '密码' })
              .type(InputType.Password).layoutWeight(1).textAlign(TextAlign.End)
          }.advRow()
          Row() {
            Text('当前身份').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Select(ALL_FAMILY_ROLES.map((r): SelectOption => ({ value: r })))
              .selected(this.roleIndex)
              .value(ALL_FAMILY_ROLES[this.roleIndex])
              .onSelect((i: number) => { this.roleIndex = i; })
          }.advRow()
          Row() {
            Text('布布名字').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.childName }).width(160).textAlign(TextAlign.End)
          }.advRow()
          Text('填好后，爸爸妈妈姥姥三台手机的记录会自动汇到一起。没配也没关系——离线全功能可用。')
            .fontSize(11).fontColor(BubuColor.secondaryText).width('100%')

          // —— AI 服务 ——
          Text('AI 服务（布布的故事）').fontSize(13).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
          Row() {
            Text('让 AI 帮忙写故事').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.aiEnabled })
              .selectedColor(BubuColor.primary)
              .onChange((v: boolean) => { this.aiEnabled = v; })
          }.advRow()
          if (this.aiEnabled) {
            Row() {
              Text('AI 地址').fontSize(15).fontColor(BubuColor.warmBrown)
              Blank()
              TextInput({ text: $$this.aiBaseURL, placeholder: ServerConfig.aiBaseURLPlaceholder })
                .layoutWeight(1).textAlign(TextAlign.End)
            }.advRow()
            Row() {
              Text('AI 访问密钥').fontSize(15).fontColor(BubuColor.warmBrown)
              Blank()
              TextInput({ text: $$this.aiAPIKey, placeholder: '服务端 AI_API_KEY' })
                .type(InputType.Password).layoutWeight(1).textAlign(TextAlign.End)
            }.advRow()
          }
          Text('关闭时用本地模拟。开启并填好地址和密钥后，改写、旁白、转写走你自托管的服务。密钥与服务器 .env 里的 AI_API_KEY 一致。')
            .fontSize(11).fontColor(BubuColor.secondaryText).width('100%')

          Button('保存并立即同步')
            .width('100%').backgroundColor(BubuColor.primary).margin({ top: 12 })
            .onClick(() => { this.saveAndSync(); })

          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(12).fontColor(BubuColor.primary).width('100%').textAlign(TextAlign.Center)
          }
        }
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  private async saveAndSync(): Promise<void> {
    const c = ServerConfig.shared;
    c.baseURLString = this.baseURL.trim().length === 0 ? ServerConfig.defaultBaseURL : this.baseURL.trim();
    c.accountEmail = this.email.trim();
    c.accountPassword = this.password;
    c.aiBaseURLString = this.aiBaseURL.trim().length === 0 ? ServerConfig.defaultAIBaseURL : this.aiBaseURL.trim();
    c.aiAPIKey = this.aiAPIKey.trim();
    c.aiEnabled = this.aiEnabled;
    await c.setRole(ALL_FAMILY_ROLES[this.roleIndex]);
    await c.setChildName(this.childName.trim().length === 0 ? '布布' : this.childName.trim());
    await c.persistServer();
    SyncEngine.shared.start();
    this.statusText = '已保存，正在同步';
    promptAction.showToast({ message: '已保存，正在同步…' });
  }
}

// MARK: - 备份健康度卡（对照 iOS BackupHealthCard，Wave L §5.5）
// 三项体检：上次同步 / 待同步 / 上次全量导出距今。任一超阈值用 warning 色提醒。
// 导出时间戳由 ExportView 完成后写入 preferences 'bubu.lastExportAt'（与 iOS @AppStorage 对应）。
@Component
export struct BackupHealthCard {
  @Prop lastExportAtSec: number = 0; // 由宿主从 preferences 读入注入（epoch 秒）

  private daysSinceExport(): number {
    if (this.lastExportAtSec <= 0) return -1;
    const lastMs = this.lastExportAtSec * 1000;
    return Math.floor((Date.now() - lastMs) / 86400000);
  }

  // 导出超 90 天或从未导出 → 提醒。
  private exportStale(): boolean {
    const d = this.daysSinceExport();
    return d < 0 || d > 90;
  }

  private exportText(): string {
    const d = this.daysSinceExport();
    if (d < 0) return '未存档';
    if (d === 0) return '今天';
    return `${d} 天前`;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(this.exportStale() ? '⚠️' : '🛡️')
          .fontSize(17).width(32).height(32).textAlign(TextAlign.Center)
          .backgroundColor(this.exportStale() ? BubuColor.warning : BubuColor.success)
          .borderRadius(9).fontColor(Color.White)
        Text('备份健康度').fontSize(BubuFont.body).fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')
      this.checkLine('上次同步', ServerConfig.shared.isConfigured ? '已连接' : '未同步', !ServerConfig.shared.isConfigured)
      this.checkLine('上次存档', this.exportText(), this.exportStale())
    }
    .padding(14)
    .width('100%')
  }

  @Builder
  checkLine(title: string, value: string, warn: boolean) {
    Row() {
      Text(title).fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
      Blank()
      Text(value)
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(warn ? BubuColor.warning : BubuColor.warmBrown)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 42 })
  }
}

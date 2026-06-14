import { ServerConfig } from '../services/ServerConfig';
import { AccountService } from '../services/AccountService';
import { SyncEngine } from '../sync/SyncEngine';
import { ALL_FAMILY_ROLES, FamilyRole } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { MembersView } from './MembersView';
import { AccountView } from './AccountView';
import { WhatsNewView } from './WhatsNewView';
import { ChildProfileView } from './ChildProfileView';
import { HealthHomeView } from './HealthHomeView';
import { VoiceArchiveView } from './VoiceArchiveView';
import { ThemeSettingsView } from './ThemeSettingsView';
import { YearbookView } from './YearbookView';
import { ExportView } from './ExportView';
import { AdvancedSettingsView } from './AdvancedSettingsView';
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { promptAction } from '@kit.ArkUI';

@Extend(Row)
function settingRow() {
  .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
}

// MARK: - 设置（对照 iOS SettingsView 核心）
// 当前身份、服务器地址/账号（驱动同步）、布布名字、立即同步。
@Component
export struct SettingsView {
  onClose?: () => void;
  @State baseURL: string = '';
  @State email: string = '';
  @State password: string = '';
  @State aiBaseURL: string = '';
  @State aiAPIKey: string = '';
  @State aiEnabled: boolean = true;
  @State childName: string = '布布';
  @State roleIndex: number = 1; // 默认妈妈
  @State showMembers: boolean = false;
  @State showAccount: boolean = false;
  @State showWhatsNew: boolean = false;
  @State showProfile: boolean = false;
  @State showHealth: boolean = false;
  @State showAdvanced: boolean = false;
  @State showVoiceArchive: boolean = false;
  @State showTheme: boolean = false;
  @State showYearbook: boolean = false;
  @State showExport: boolean = false;
  @State statusText: string = '';
  @State isPullingServer: boolean = false;

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
    if (this.showMembers) {
      this.membersPage()
    } else if (this.showAccount) {
      this.accountPage()
    } else if (this.showWhatsNew) {
      this.whatsNewPage()
    } else if (this.showProfile) {
      this.profilePage()
    } else if (this.showHealth) {
      this.healthPage()
    } else if (this.showAdvanced) {
      this.advancedPage()
    } else if (this.showVoiceArchive) {
      this.voiceArchivePage()
    } else if (this.showTheme) {
      this.themePage()
    } else if (this.showYearbook) {
      this.yearbookPage()
    } else if (this.showExport) {
      this.exportPage()
    } else {
      this.mainPage()
    }
  }

  @Builder
  membersPage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showMembers = false; })
        Text('家庭成员')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      MembersView()
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  accountPage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showAccount = false; })
        Text('家人登录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      AccountView({
        onDone: () => {
          this.showAccount = false;
          this.aboutToAppear();
          SyncEngine.shared.start();
        }
      })
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  whatsNewPage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showWhatsNew = false; })
        Text('更新记录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      WhatsNewView()
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  profilePage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showProfile = false; })
        Text('布布的档案')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      ChildProfileView()
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  healthPage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showHealth = false; })
        Text('健康记录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      HealthHomeView()
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          if (this.onClose) {
            Button('返回')
              .backgroundColor('#F3F3F3')
              .fontColor(BubuColor.warmBrown)
              .onClick(() => { this.onClose!(); })
          }
          Text('设置')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%')

        Row({ space: 14 }) {
          Text(ServerConfig.shared.isConfigured ? '🙂' : '👤')
            .fontSize(34)
            .width(60)
            .height(60)
            .textAlign(TextAlign.Center)
            .backgroundColor('#FFF0F4')
            .borderRadius(30)
          Column({ space: 4 }) {
            Text(ServerConfig.shared.isConfigured ? AccountService.usernameFor(this.email) : '未设置')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown)
            Text(ServerConfig.shared.isConfigured ? `${ALL_FAMILY_ROLES[this.roleIndex]} · 点我换人` : '家人各自登录，记录会署名保存')
              .fontSize(12)
              .fontColor(BubuColor.secondaryText)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.syncText())
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#F3F3F3')
            .borderRadius(14)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(BubuColor.card)
        .borderRadius(20)
        .onClick(() => { this.showMembers = true; })

        this.bubuGroup()
        this.familyGroup()
        this.appearanceGroup()
        this.dataGroup()
        this.advancedGroup()
        this.aboutGroup()

        Text('离线也能用：所有记录先存手机，连上服务器后自动同步给全家。')
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
          .width('100%')
          .textAlign(TextAlign.Center)
        Text(`布布时光机 v${ServerConfig.versionName} (${ServerConfig.versionCode})`)
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  @Builder
  advancedPage() {
    AdvancedSettingsView({ onClose: () => { this.showAdvanced = false; this.aboutToAppear(); } })
  }

  @Builder
  voiceArchivePage() {
    VoiceArchiveView({ onClose: () => { this.showVoiceArchive = false; } })
  }

  @Builder
  themePage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showTheme = false; })
        Text('主题与外观')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      ThemeSettingsView()
        .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  yearbookPage() {
    YearbookView({ onClose: () => { this.showYearbook = false; } })
  }

  @Builder
  exportPage() {
    ExportView({ onClose: () => { this.showExport = false; } })
  }

  @Builder
  bubuGroup() {
    Column({ space: 10 }) {
      Text('布布')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.navRow('布布的档案', '👧', '生日、性别、血型、头像和首页背景', () => { this.showProfile = true; })
        this.navRow('成长之声', '🎙️', '按一岁一岁收好布布的声音和家人寄语', () => { this.showVoiceArchive = true; })
        this.navRow('健康记录', '🩺', '餐食、零食、营养补充、睡眠和不舒服', () => { this.showHealth = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  familyGroup() {
    Column({ space: 10 }) {
      Text('这个家')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.navRow('家人登录', '👤', ServerConfig.shared.isConfigured ? '切换账号或退出当前账号' : '用户名 + 家庭码加入', () => { this.showAccount = true; })
        this.navRow('家庭成员', '👨‍👩‍👧', '管理家人的名字、关系和头像', () => { this.showMembers = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  appearanceGroup() {
    Column({ space: 10 }) {
      Text('外观')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.navRow('主题与外观', '🎨', '马卡龙主题配色与首页背景', () => { this.showTheme = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  dataGroup() {
    Column({ space: 10 }) {
      Text('数据')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.infoRow('备份健康度', BubuIconName.checkCloud, ServerConfig.shared.isConfigured ? '已连接家里的服务器' : '离线也能用，登录后自动同步', ServerConfig.shared.isConfigured ? '已配置' : '未登录')
        this.navRow(this.isPullingServer ? '正在从服务器同步' : '从服务器同步到本机', BubuIconName.sync, '补齐 iOS 上传的时光、里程碑、健康和媒体', () => { this.pullServerToLocal(); })
        this.navRow('做一本 PDF 年册', BubuIconName.photo, '把布布的一年做成可打印的书', () => { this.showYearbook = true; })
        this.navRow('导出布布的全量档案', BubuIconName.send, '网页 + 全部媒体，永久离线可读', () => { this.showExport = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  advancedGroup() {
    Column({ space: 10 }) {
      Text('高级 · 自托管')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.navRow('服务器与 AI 配置', BubuIconName.gear, '给装服务器的那个人', () => { this.showAdvanced = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  aboutGroup() {
    Column({ space: 10 }) {
      Text('关于')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.navRow('更新记录', BubuIconName.sparkles, `当前版本 v${ServerConfig.versionName}`, () => { this.showWhatsNew = true; })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
    .width('100%')
  }

  @Builder
  navRow(title: string, icon: string, subtitle: string, action: () => void) {
    Row({ space: 14 }) {
      BubuIconBadge({
        name: this.iconName(icon),
        badgeSize: 36,
        iconSize: 19,
        color: BubuColor.primary,
        fill: '#FFF0F4',
        radius: 10,
        strokeWidth: 2.1,
        filled: this.iconName(icon) === BubuIconName.sparkles
      })
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(BubuColor.warmBrown)
        Text(subtitle).fontSize(11).fontColor(BubuColor.secondaryText).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(18).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .onClick(action)
  }

  @Builder
  infoRow(title: string, icon: string, subtitle: string, value: string) {
    Row({ space: 14 }) {
      BubuIconBadge({
        name: this.iconName(icon),
        badgeSize: 36,
        iconSize: 19,
        color: BubuColor.primary,
        fill: '#FFF0F4',
        radius: 10,
        strokeWidth: 2.1
      })
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(BubuColor.warmBrown)
        Text(subtitle).fontSize(11).fontColor(BubuColor.secondaryText).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(value).fontSize(12).fontColor(BubuColor.primary)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }

  private syncText(): string {
    return ServerConfig.shared.isConfigured ? '已同步' : '离线';
  }

  private iconName(icon: string): string {
    switch (icon) {
      case BubuIconName.checkCloud:
      case BubuIconName.sync:
      case BubuIconName.photo:
      case BubuIconName.send:
      case BubuIconName.gear:
      case BubuIconName.sparkles:
      case BubuIconName.health:
      case BubuIconName.mic:
        return icon;
      case '👧': return BubuIconName.sparkles;
      case '🎙️': return BubuIconName.mic;
      case '🩺': return BubuIconName.health;
      case '👤': return BubuIconName.home;
      case '👨‍👩‍👧': return BubuIconName.home;
      case '🎨': return BubuIconName.sparkles;
      default: return BubuIconName.sparkles;
    }
  }

  private async pullServerToLocal(): Promise<void> {
    if (this.isPullingServer) return;
    if (!ServerConfig.shared.isConfigured) {
      promptAction.showToast({ message: '请先登录服务器账号' });
      return;
    }
    this.isPullingServer = true;
    promptAction.showToast({ message: '开始从服务器同步到本机' });
    const message = await SyncEngine.shared.pullServerToLocalNow();
    this.isPullingServer = false;
    promptAction.showToast({ message: message });
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

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
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor('#F3F3F3')
          .fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showAdvanced = false; })
        Text('服务器与 AI 配置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 14 }) {
          this.infoRow('远端服务器', '🏠', '已内置，与 iOS 1.2.0 一致', '正常')
          Row() {
            Text('地址').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.baseURL, placeholder: ServerConfig.baseURLPlaceholder }).layoutWeight(1).textAlign(TextAlign.End)
          }.settingRow()
          Row() {
            Text('用户名/账号').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.email, placeholder: 'username@bubu.family' }).layoutWeight(1).textAlign(TextAlign.End)
          }.settingRow()
          Row() {
            Text('密码').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.password, placeholder: '密码' }).type(InputType.Password).layoutWeight(1).textAlign(TextAlign.End)
          }.settingRow()
          Row() {
            Text('当前身份').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Select(ALL_FAMILY_ROLES.map((r): SelectOption => ({ value: r })))
              .selected(this.roleIndex)
              .value(ALL_FAMILY_ROLES[this.roleIndex])
              .onSelect((i: number) => { this.roleIndex = i; })
          }.settingRow()
          Row() {
            Text('布布名字').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.childName }).width(160).textAlign(TextAlign.End)
          }.settingRow()

          Text('AI 助手').fontSize(13).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
          Row() {
            Text('启用 AI').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.aiEnabled })
              .onChange((v: boolean) => { this.aiEnabled = v; })
          }.settingRow()
          Row() {
            Text('AI 地址').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.aiBaseURL, placeholder: ServerConfig.aiBaseURLPlaceholder }).layoutWeight(1).textAlign(TextAlign.End)
          }.settingRow()

          Button('保存并立即同步')
            .width('100%').backgroundColor(BubuColor.primary).margin({ top: 12 })
            .onClick(() => { this.saveAndSync(); })

          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(12)
              .fontColor(BubuColor.primary)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
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
  dataGroup() {
    Column({ space: 10 }) {
      Text('数据')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText)
        .width('100%')
        .padding({ left: 6 })
      Column({ space: 0 }) {
        this.infoRow('备份健康度', '🛡️', ServerConfig.shared.isConfigured ? '已连接家里的服务器' : '离线也能用，登录后自动同步', ServerConfig.shared.isConfigured ? '已配置' : '未登录')
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
        this.navRow('服务器与 AI 配置', '🔐', '给装服务器的那个人', () => { this.showAdvanced = true; })
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
        this.navRow('更新记录', '✨', `当前版本 v${ServerConfig.versionName}`, () => { this.showWhatsNew = true; })
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
      Text(icon)
        .fontSize(20)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFF0F4')
        .borderRadius(10)
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
      Text(icon)
        .fontSize(20)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFF0F4')
        .borderRadius(10)
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

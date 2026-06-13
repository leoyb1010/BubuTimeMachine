import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';
import { ALL_FAMILY_ROLES, FamilyRole } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { MembersView } from './MembersView';
import { promptAction } from '@kit.ArkUI';

@Extend(Row)
function settingRow() {
  .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
}

// MARK: - 设置（对照 iOS SettingsView 核心）
// 当前身份、服务器地址/账号（驱动同步）、布布名字、立即同步。
@Component
export struct SettingsView {
  @State baseURL: string = '';
  @State email: string = '';
  @State password: string = '';
  @State childName: string = '布布';
  @State roleIndex: number = 1; // 默认妈妈
  @State showMembers: boolean = false;

  aboutToAppear(): void {
    const c = ServerConfig.shared;
    this.baseURL = c.baseURLString;
    this.email = c.accountEmail;
    this.password = c.accountPassword;
    this.childName = c.childName;
    this.roleIndex = Math.max(0, ALL_FAMILY_ROLES.indexOf(c.currentRole));
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')

        Text('我是谁').fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
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

        Text('家里的服务器（同步用）').fontSize(13).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
        Row() {
          Text('地址').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          TextInput({ text: $$this.baseURL, placeholder: 'https://你的地址:8090' }).layoutWeight(1).textAlign(TextAlign.End)
        }.settingRow()
        Row() {
          Text('账号').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          TextInput({ text: $$this.email, placeholder: '邮箱' }).layoutWeight(1).textAlign(TextAlign.End)
        }.settingRow()
        Row() {
          Text('密码').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          TextInput({ text: $$this.password, placeholder: '密码' }).type(InputType.Password).layoutWeight(1).textAlign(TextAlign.End)
        }.settingRow()

        // 家庭成员入口
        Row() {
          Text('家庭成员').fontSize(15).fontColor(BubuColor.warmBrown)
          Blank()
          Text('管理 ›').fontSize(14).fontColor(BubuColor.primary)
        }.settingRow().margin({ top: 8 })
        .onClick(() => { this.showMembers = true; })

        Button('保存并立即同步')
          .width('100%').backgroundColor(BubuColor.primary).margin({ top: 12 })
          .onClick(() => { this.saveAndSync(); })

        Text('离线也能用：所有记录先存手机，连上服务器后自动同步给全家。')
          .fontSize(11).fontColor(BubuColor.secondaryText).margin({ top: 8 })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
    .bindSheet($$this.showMembers, this.membersSheet(), { height: '85%' })
  }

  @Builder
  membersSheet() {
    MembersView()
  }

  private async saveAndSync(): Promise<void> {
    const c = ServerConfig.shared;
    c.baseURLString = this.baseURL.trim();
    c.accountEmail = this.email.trim();
    c.accountPassword = this.password;
    await c.setRole(ALL_FAMILY_ROLES[this.roleIndex]);
    await c.setChildName(this.childName.trim().length === 0 ? '布布' : this.childName.trim());
    await c.persistServer();
    SyncEngine.shared.start();
    promptAction.showToast({ message: '已保存，正在同步…' });
  }
}

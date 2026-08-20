import { ALL_FAMILY_ROLES, FamilyRole } from '../models/Enums';
import { ServerConfig } from '../services/ServerConfig';
import { AccountService } from '../services/AccountService';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { CapsuleRecoveryView } from './CapsuleRecoveryView';
import { SyncEngine } from '../sync/SyncEngine';

@Component
export struct AccountView {
  onDone?: () => void;

  @State username: string = '';
  @State password: string = '';
  @State roleIndex: number = 1;
  @State busy: boolean = false;
  @State errorText: string = '';
  @State showChangePassword: boolean = false;
  @State showRecovery: boolean = false;
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';

  private service: AccountService = new AccountService();

  aboutToAppear(): void {
    const cfg = ServerConfig.shared;
    this.username = AccountService.usernameFor(cfg.accountEmail);
    this.password = '';
    this.roleIndex = Math.max(0, ALL_FAMILY_ROLES.indexOf(cfg.currentRole));
  }

  build() {
    if (this.showRecovery) {
      CapsuleRecoveryView({ onBack: () => { this.showRecovery = false; } })
    } else if (this.showChangePassword) {
      this.changePasswordPage()
    } else {
      this.accountPage()
    }
  }

  @Builder
  accountPage() {
    Scroll() {
      Column({ space: 16 }) {
        Text(ServerConfig.shared.isConfigured ? '🏡' : '👨‍👩‍👧').fontSize(44)
        Text(ServerConfig.shared.isConfigured ? AccountService.usernameFor(ServerConfig.shared.accountEmail) : '一家人，各自登录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(ServerConfig.shared.isConfigured ? `当前署名：${ServerConfig.shared.currentRoleRaw}` : '大家看的是同一个布布，署名各自清楚')
          .fontSize(12)
          .fontColor(BubuColor.secondaryText)

        if (ServerConfig.shared.isConfigured) {
          Column({ space: 10 }) {
            this.infoRow('账号', ServerConfig.shared.accountEmail)
            this.infoRow('服务器', ServerConfig.shared.baseURLString)
            this.infoRow('连接', this.connectionText())
          }
          .width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(16)

          Button('修改密码').width('100%').backgroundColor(BubuColor.card).fontColor(BubuColor.warmBrown)
            .onClick(() => { this.showChangePassword = true; })
          Button('家庭恢复码').width('100%').backgroundColor(BubuColor.card).fontColor(BubuColor.warmBrown)
            .onClick(() => { this.showRecovery = true; })
          Button('退出当前账号').width('100%').backgroundColor('#FFE5E5').fontColor('#D9534F')
            .onClick(() => { this.confirmLogout(); })
        } else {
          Column({ space: 12 }) {
          TextInput({ text: $$this.username, placeholder: '用户名（如 yuanbo）' })
            .height(48)
            .backgroundColor(BubuColor.softFill)
            .borderRadius(10)
          TextInput({ text: $$this.password, placeholder: '密码' })
            .height(48)
            .backgroundColor(BubuColor.softFill)
            .borderRadius(10)
            .type(InputType.Password)
          Row() {
            Text('我是').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Select(ALL_FAMILY_ROLES.map((r): SelectOption => ({ value: r })))
              .selected(this.roleIndex)
              .value(ALL_FAMILY_ROLES[this.roleIndex])
              .onSelect((i: number) => { this.roleIndex = i; })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(BubuColor.card)
        .borderRadius(16)

          if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#D9534F')
            .textAlign(TextAlign.Center)
            .width('100%')
        }

          Button(this.busy ? '处理中…' : '登录')
          .width('100%')
          .backgroundColor(BubuColor.primary)
          .enabled(!this.busy)
          .onClick(() => { this.submit(); })

        }
      }
      .padding(20)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream)
    .width('100%')
    .height('100%')
  }

  @Builder
  infoRow(title: string, value: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(12).fontColor(BubuColor.secondaryText).width(52)
      Text(value).fontSize(13).fontColor(BubuColor.warmBrown).layoutWeight(1).maxLines(2)
    }.width('100%')
  }

  @Builder
  changePasswordPage() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('返回').onClick(() => { this.showChangePassword = false; })
        Text('修改密码').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')
      TextInput({ text: $$this.oldPassword, placeholder: '当前密码' }).type(InputType.Password).height(48)
      TextInput({ text: $$this.newPassword, placeholder: '新密码（至少 8 位）' }).type(InputType.Password).height(48)
      TextInput({ text: $$this.confirmPassword, placeholder: '再输一次新密码' }).type(InputType.Password).height(48)
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(12).fontColor(BubuColor.danger).width('100%')
      }
      Button(this.busy ? '保存中…' : '保存新密码')
        .width('100%').backgroundColor(BubuColor.primary).enabled(!this.busy)
        .onClick(() => { this.changePassword(); })
      Text('修改后这台设备会自动使用新密码；其他家人的设备需要各自重新登录。')
        .fontSize(12).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
    }.padding(20).width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  private connectionText(): string {
    const status = SyncEngine.shared.statusSnapshot();
    if (status.syncing || status.state === 'connecting') return '连接中';
    return status.state === 'online' ? '已连接' : '离线（本地可用）';
  }

  private async submit(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.errorText = '';
    const role = ALL_FAMILY_ROLES[Math.max(0, Math.min(this.roleIndex, ALL_FAMILY_ROLES.length - 1))] as FamilyRole;
    try {
      await this.service.login(this.username, this.password, role);
      this.password = '';
      SyncEngine.shared.start();
      this.getUIContext().getPromptAction().showToast({ message: '已登录，开始同步' });
      if (this.onDone) this.onDone();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '登录失败，请稍后再试';
    }
    this.busy = false;
  }

  private async logout(): Promise<void> {
    await this.service.logout();
    this.username = '';
    this.password = '';
    this.getUIContext().getPromptAction().showToast({ message: '已退出当前账号' });
    if (this.onDone) this.onDone();
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '要退出这个账号吗？',
      message: '退出后停止同步，但本机已有的照片和记录都会保留，随时可以重新登录。',
      primaryButton: { value: '退出登录', fontColor: BubuColor.danger, action: () => { this.logout(); } },
      secondaryButton: { value: '再想想', action: () => {} }
    });
  }

  private async changePassword(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.errorText = '';
    try {
      await this.service.changePassword(this.oldPassword, this.newPassword, this.confirmPassword);
      this.oldPassword = '';
      this.newPassword = '';
      this.confirmPassword = '';
      this.showChangePassword = false;
      SyncEngine.shared.start();
      this.getUIContext().getPromptAction().showToast({ message: '密码已更新' });
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '修改密码失败';
    }
    this.busy = false;
  }
}

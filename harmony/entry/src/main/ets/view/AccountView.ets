import { ALL_FAMILY_ROLES, FamilyRole } from '../models/Enums';
import { ServerConfig } from '../services/ServerConfig';
import { AccountService } from '../services/AccountService';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

@Component
export struct AccountView {
  onDone?: () => void;

  @State username: string = '';
  @State password: string = '';
  @State roleIndex: number = 1;
  @State busy: boolean = false;
  @State errorText: string = '';

  private service: AccountService = new AccountService();

  aboutToAppear(): void {
    const cfg = ServerConfig.shared;
    this.username = AccountService.usernameFor(cfg.accountEmail);
    this.password = cfg.accountPassword;
    this.roleIndex = Math.max(0, ALL_FAMILY_ROLES.indexOf(cfg.currentRole));
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('👨‍👩‍👧').fontSize(44)
        Text('一家人，各自登录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('大家看的是同一个布布，署名各自清楚')
          .fontSize(12)
          .fontColor(BubuColor.secondaryText)

        Column({ space: 12 }) {
          TextInput({ text: $$this.username, placeholder: '用户名（如 yuanbo）' })
            .height(48)
            .backgroundColor('#F3F3F3')
            .borderRadius(10)
          TextInput({ text: $$this.password, placeholder: '密码' })
            .height(48)
            .backgroundColor('#F3F3F3')
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

        if (ServerConfig.shared.isConfigured) {
          Button('退出当前账号')
            .width('100%')
            .backgroundColor('#FFE5E5')
            .fontColor('#D9534F')
            .onClick(() => { this.logout(); })
        }
      }
      .padding(20)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream)
    .width('100%')
    .height('100%')
  }

  private async submit(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.errorText = '';
    const role = ALL_FAMILY_ROLES[Math.max(0, Math.min(this.roleIndex, ALL_FAMILY_ROLES.length - 1))] as FamilyRole;
    try {
      await this.service.login(this.username, this.password, role);
      promptAction.showToast({ message: '已登录，开始同步' });
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
    promptAction.showToast({ message: '已退出当前账号' });
    if (this.onDone) this.onDone();
  }
}

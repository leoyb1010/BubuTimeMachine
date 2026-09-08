import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BubuColor } from '../theme/BubuTheme';

// 版本迁移提示只出现一次；确认后写本机 Preferences，不进入家庭同步。
@Component
export struct BubuMovedHint {
  @Require @Prop storageKey: string;
  @Require @Prop message: string;
  @State private visible: boolean = false;

  async aboutToAppear(): Promise<void> {
    try {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = await preferences.getPreferences(context, 'bubu_moved_hints');
    this.visible = !(await store.get(this.storageKey, false) as boolean);
    } catch (error) {
      this.visible = false; hilog.warn(0x0000, 'Bubu', '迁移提示状态暂不可读');
    }
  }

  build() {
    if (this.visible) {
      Row({ space: 10 }) {
        Text(this.message).fontSize(11).fontColor(BubuColor.secondaryText).layoutWeight(1)
        Text('知道了').fontSize(11).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
          .onClick(() => { this.dismiss(); })
      }
      .width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor('#66FFFFFF').borderRadius(14)
    }
  }

  private async dismiss(): Promise<void> {
    try {
    this.visible = false;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = await preferences.getPreferences(context, 'bubu_moved_hints');
    await store.put(this.storageKey, true);
    await store.flush();
    } catch (error) {
      hilog.warn(0x0000, 'Bubu', '迁移提示未持久保存，下次可再次确认');
    }
  }
}

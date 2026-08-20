import { common } from '@kit.AbilityKit';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';

// 数据库/迁移失败专用保护页：不依赖 AppDatabase，不触发新人引导、同步或任何写入。
@Entry
@Component
struct DataProtectionPage {
  build() {
    Column({ space: 18 }) {
      Text('🛡️').fontSize(54)
      Text('已保护本机档案')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text('本地数据库暂时无法安全打开。布布时光机没有删除、重建或覆盖原文件，也没有启动同步。')
        .fontSize(15)
        .fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
      Text('请先保留 App 和手机数据，关闭后重试；若仍出现，请导出设备诊断后再处理，不要卸载 App。')
        .fontSize(13)
        .fontColor(BubuColor.danger)
        .textAlign(TextAlign.Center)
      Button('关闭 App 后重试')
        .width('100%')
        .height(50)
        .backgroundColor(BubuColor.primary)
        .fontColor(Color.White)
        .borderRadius(BubuRadius.button)
        .onClick(() => {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          context.terminateSelf();
        })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .padding(28)
    .backgroundColor(BubuColor.background)
  }
}

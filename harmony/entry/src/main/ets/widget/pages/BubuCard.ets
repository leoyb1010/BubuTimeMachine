// MARK: - 服务卡片 UI（ArkTS 卡片，对照 iOS 小组件身份卡）
@Entry
@Component
struct BubuCard {
  @LocalStorageProp('name') name: string = '布布';
  @LocalStorageProp('ageText') ageText: string = '记录布布的成长';
  @LocalStorageProp('daysText') daysText: string = '';

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('🍼').fontSize(20)
        Text(this.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#5C473D').margin({ left: 4 })
      }
      Text(this.ageText)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#5C473D')
        .maxLines(2).textAlign(TextAlign.Center)
      if (this.daysText.length > 0) {
        Text(this.daysText).fontSize(11).fontColor('#8C8078')
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .padding(12)
    .linearGradient({
      angle: 135,
      colors: [['#FFFFFF', 0.0], ['#FFF1F3', 0.6], ['#FDE8EC', 1.0]]
    })
    // 点卡片拉起 App
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility'
      } as Record<string, string>);
    })
  }
}

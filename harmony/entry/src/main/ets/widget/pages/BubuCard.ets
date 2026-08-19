// MARK: - 服务卡片 UI（ArkTS 卡片，对照 iOS 小组件身份卡）
const storage = new LocalStorage();

@Entry(storage)
@Component
struct BubuCard {
  @LocalStorageProp('name') name: string = '布布';
  @LocalStorageProp('ageText') ageText: string = '记录布布的成长';
  @LocalStorageProp('daysText') daysText: string = '';
  @LocalStorageProp('recentTitle') recentTitle: string = '记录一个新瞬间';
  @LocalStorageProp('recentNote') recentNote: string = '打开 App，留住今天的成长';
  @LocalStorageProp('statsText') statsText: string = '0 条时光 · 0 张照片';
  @LocalStorageProp('growthText') growthText: string = '还没有成长测量';
  @LocalStorageProp('nextMilestone') nextMilestone: string = '记录新的第一次';

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
      Divider().color('#33A98D82').margin({ top: 2, bottom: 2 })
      Text(this.recentTitle).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#5C473D').maxLines(1)
      Text(this.recentNote).fontSize(10).fontColor('#8C8078').maxLines(2).textAlign(TextAlign.Center)
      Text(this.statsText).fontSize(9).fontColor('#F2789F').maxLines(1)
      Text(`${this.growthText} · 下一颗星：${this.nextMilestone}`).fontSize(9).fontColor('#8C8078').maxLines(1)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .padding(10)
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

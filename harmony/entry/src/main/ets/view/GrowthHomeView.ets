import { FirstTime, GrowthMeasurement, HealthRecord, Milestone, VaccineRecord } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { GrowthCurveView } from './GrowthCurveView';
import { HealthHomeView } from './HealthHomeView';
import { VaccineView } from './VaccineView';
import { MilestonesView } from './MilestonesView';
import { BackDispatcher } from '../services/BackDispatcher';

@Component
export struct GrowthHomeView {
  onBack: () => void = () => {};
  showBack: boolean = true;

  @State @Watch('syncBackHandler') route: string = '';
  @State milestones: Milestone[] = [];
  @State measurements: GrowthMeasurement[] = [];
  @State health: HealthRecord[] = [];
  @State vaccines: VaccineRecord[] = [];
  @State firstTimes: FirstTime[] = [];

  aboutToAppear(): void { this.reload(); this.syncBackHandler(); }

  aboutToDisappear(): void { BackDispatcher.shared.unregister('growth-home'); }

  private syncBackHandler(): void {
    if (this.route.length > 0) {
      BackDispatcher.shared.register('growth-home', 5, (): boolean => {
        if (this.route.length === 0) return false;
        this.route = '';
        return true;
      });
    } else {
      BackDispatcher.shared.unregister('growth-home');
    }
  }

  build() {
    if (this.route === 'curve') {
      Column() { this.header('成长数据', () => { this.route = ''; }); GrowthCurveView().layoutWeight(1) }
        .width('100%').height('100%').backgroundColor(BubuColor.background)
    } else if (this.route === 'health') {
      Column() { this.header('健康', () => { this.route = ''; }); HealthHomeView().layoutWeight(1) }
        .width('100%').height('100%').backgroundColor(BubuColor.background)
    } else if (this.route === 'vaccine') {
      Column() { this.header('疫苗接种', () => { this.route = ''; }); VaccineView().layoutWeight(1) }
        .width('100%').height('100%').backgroundColor(BubuColor.background)
    } else if (this.route === 'milestones') {
      Column() { this.header('里程碑', () => { this.route = ''; }, true); MilestonesView().layoutWeight(1) }
        .width('100%').height('100%').backgroundColor(BubuColor.background)
    } else {
      Column() {
        this.header('成长', this.onBack, this.showBack)
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 7 }) {
              Text('布布正在慢慢长大')
                .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text(this.overviewText()).fontSize(14).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
            }.width('100%').padding(18).backgroundColor('#18F28C9E').borderRadius(BubuRadius.card)

            Row({ space: 10 }) {
              this.linkCard(BubuIconName.sync, '成长数据', this.measurementSubtitle(), () => { this.route = 'curve'; })
              this.linkCard(BubuIconName.star, '里程碑', `已点亮 ${this.achieved().length} 个`, () => { this.route = 'milestones'; })
            }.width('100%')
            Row({ space: 10 }) {
              this.linkCard(BubuIconName.health, '健康', `共 ${this.health.length} 条记录`, () => { this.route = 'health'; })
              this.linkCard(BubuIconName.plus, '疫苗接种', `已记录 ${this.vaccines.length} 剂`, () => { this.route = 'vaccine'; })
            }.width('100%')

            Column({ space: 10 }) {
              Row() {
                Text('第一次').fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
                Blank()
                Text(`${this.firstTimes.length} 条`).fontSize(13).fontColor(BubuColor.primary)
              }.width('100%')
              if (this.firstTimes.length === 0) {
                Text('记录里被确认的“第一次”会自动汇到这里。').fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
              }
              ForEach(this.firstTimes.slice(0, 3), (item: FirstTime) => {
                Row({ space: 10 }) {
                  Text('⚑').fontSize(20).fontColor(BubuColor.primary)
                  Column({ space: 2 }) {
                    Text(item.what).fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
                    Text(new Date(item.happenedAt).toLocaleDateString('zh-CN')).fontSize(12).fontColor(BubuColor.secondaryText)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }.width('100%').padding({ top: 4, bottom: 4 })
              }, (item: FirstTime): string => item.id)
            }.width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)

            if (this.achieved().length > 0) {
              Row({ space: 12 }) {
                Text(this.achieved()[0].emoji).fontSize(30)
                Column({ space: 3 }) {
                  Text('最近点亮').fontSize(12).fontColor(BubuColor.primary)
                  Text(this.achieved()[0].title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('›').fontSize(20).fontColor(BubuColor.secondaryText)
              }.width('100%').padding(16).backgroundColor('#14F28C9E').borderRadius(BubuRadius.card)
              .onClick(() => { this.route = 'milestones'; })
            }
          }.width('100%').padding(16)
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.background)
    }
  }

  @Builder
  private header(title: string, action: () => void, showBack: boolean = true) {
    Row({ space: 8 }) {
      if (showBack) {
        Button('‹ 返回').backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown).onClick(action)
      } else {
        Blank().width(72)
      }
      Blank()
      Text(title).fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Blank()
      Text('       ')
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 8 })
  }

  @Builder
  private linkCard(icon: string, title: string, subtitle: string, action: () => void) {
    Column({ space: 9 }) {
      BubuIconBadge({ name: icon, badgeSize: 42, iconSize: 21, color: BubuColor.primary,
        fill: '#1FF28C9E', radius: 21, strokeWidth: 2.2 })
      Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(subtitle).fontSize(12).fontColor(BubuColor.secondaryText).maxLines(2).textAlign(TextAlign.Center)
    }.layoutWeight(1).height(130).justifyContent(FlexAlign.Center)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card).onClick(action)
  }

  private async reload(): Promise<void> {
    this.milestones = await AppDatabase.shared.fetchMilestones();
    this.measurements = await AppDatabase.shared.fetchGrowth();
    this.health = await AppDatabase.shared.fetchHealth();
    this.vaccines = await AppDatabase.shared.fetchVaccines();
    this.firstTimes = await AppDatabase.shared.fetchFirstTimes();
  }

  private achieved(): Milestone[] {
    return this.milestones.filter((item: Milestone): boolean => item.happenedAt !== undefined)
      .sort((left: Milestone, right: Milestone): number => (right.happenedAt ?? 0) - (left.happenedAt ?? 0));
  }

  private overviewText(): string {
    const parts: string[] = [];
    if (this.achieved().length > 0) parts.push(`点亮了 ${this.achieved().length} 个里程碑`);
    const latest = this.measurements[0];
    if (latest?.heightCm !== undefined) parts.push(`身高 ${latest.heightCm} cm`);
    if (latest?.weightKg !== undefined) parts.push(`体重 ${latest.weightKg} kg`);
    if (this.vaccines.length > 0) parts.push(`留下 ${this.vaccines.length} 条疫苗记录`);
    return parts.length > 0 ? `${parts.join('；')}。` : '从一次测量、一个第一次或一颗新星开始记录。';
  }

  private measurementSubtitle(): string {
    return this.measurements.length === 0 ? '还没有实测数据'
      : `最近更新于 ${new Date(this.measurements[0].measuredAt).toLocaleDateString('zh-CN')}`;
  }
}

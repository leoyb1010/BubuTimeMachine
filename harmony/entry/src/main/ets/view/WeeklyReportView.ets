import { Entry } from '../models/Models';
import { ArtifactSourceReference, WeeklyReport, WeeklyReportSection } from '../models/AIArtifacts';
import { AppDatabase } from '../data/AppDatabase';
import { AIService } from '../services/AIService';
import { WeeklyReportNotifier } from '../services/WeeklyReportNotifier';
import { common } from '@kit.AbilityKit';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { EntryDetailView } from './EntryDetailView';

@Component
export struct WeeklyReportView {
  onBack: () => void = () => {};

  @State report: WeeklyReport | null = null;
  @State history: WeeklyReport[] = [];
  @State loading: boolean = true;
  @State operation: string = '';
  @State errorText: string = '';
  @State selectedEntry: Entry | null = null;

  aboutToAppear(): void {
    this.load();
  }

  build() {
    if (this.selectedEntry) {
      Column() {
        this.header('周报出处', () => { this.selectedEntry = null; })
        EntryDetailView({ entry: this.selectedEntry!, onDismiss: () => { this.selectedEntry = null; } })
          .layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.background)
    } else {
      Column() {
        this.header('布布周报', this.onBack)
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 8 }) {
              Text('把一周轻轻收好')
                .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text('每段内容都带真实出处；材料不足时不会编造。')
                .fontSize(13).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
            }
            .width('100%').padding(18)
            .backgroundColor('#14F28C9E').borderRadius(BubuRadius.card)

            if (this.loading) {
              Row({ space: 10 }) {
                LoadingProgress().width(24).height(24).color(BubuColor.primary)
                Text('正在读取家里的周报…').fontColor(BubuColor.secondaryText)
              }.width('100%').padding(20)
            } else if (this.report) {
              this.reportContent(this.report!)
            } else {
              this.emptyState()
            }

            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(13).fontColor(BubuColor.danger)
                .width('100%').padding(12)
                .backgroundColor('#14DB3B47').borderRadius(BubuRadius.small)
            }

            if (this.history.length > 1) {
              Text('往期周报').fontSize(14).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText).width('100%')
              ForEach(this.history, (item: WeeklyReport) => {
                Button(`${this.weekText(item)} · ${item.status === 'archived' ? '已归档' : '待确认'}`)
                  .width('100%').height(48)
                  .backgroundColor(BubuColor.card).fontColor(BubuColor.warmBrown)
                  .borderRadius(BubuRadius.small)
                  .onClick(() => { this.report = item; })
              }, (item: WeeklyReport): string => item.id)
            }
          }.width('100%').padding(16)
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.background)
    }
  }

  @Builder
  private header(title: string, action: () => void) {
    Row({ space: 8 }) {
      Button('‹ 返回').backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown).onClick(action)
      Blank()
      Text(title).fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Blank()
      Text('       ')
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 8 })
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Text('还没有周报').fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(AIService.shared.isConfigured
        ? '周报需要一周的真实记录和至少一段原声。'
        : '请先在设置里连接家里的 AI 服务。')
        .fontSize(13).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
      Button(this.operation === 'generating' ? '正在生成…' : '生成上周周报')
        .height(48).width('100%')
        .enabled(AIService.shared.isConfigured && this.operation.length === 0)
        .backgroundColor(AIService.shared.isConfigured ? BubuColor.primary : BubuColor.softFill)
        .fontColor(AIService.shared.isConfigured ? Color.White : BubuColor.secondaryText)
        .borderRadius(BubuRadius.button)
        .onClick(() => { this.generate(); })
    }
    .width('100%').padding(22)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  @Builder
  private reportContent(report: WeeklyReport) {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text(report.title).fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Text(this.weekText(report)).fontSize(13).fontColor(BubuColor.secondaryText)
        Text(report.summary).fontSize(15).fontColor(BubuColor.warmBrown).width('100%')
      }
      .alignItems(HorizontalAlign.Start).width('100%')
      .padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)

      ForEach(report.sections, (section: WeeklyReportSection) => {
        Column({ space: 8 }) {
          Text(section.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
          Text(section.text).fontSize(15).fontColor(BubuColor.warmBrown).width('100%')
          ForEach(section.sourceIds, (sourceId: string) => {
            if (this.sourceFor(report, sourceId)) {
              Button(this.sourceTitle(this.sourceFor(report, sourceId)!))
                .width('100%').height(44)
                .backgroundColor(BubuColor.softFill).fontColor(BubuColor.secondaryText)
                .borderRadius(12)
                .onClick(() => { this.openSource(this.sourceFor(report, sourceId)!); })
            }
          }, (sourceId: string): string => sourceId)
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
      }, (section: WeeklyReportSection): string => section.kind)

      if (report.status !== 'archived') {
        Button(this.operation === 'archiving' ? '正在收进档案…' : '确认并收进档案')
          .width('100%').height(50)
          .enabled(this.operation.length === 0)
          .backgroundColor(BubuColor.primary).fontColor(Color.White)
          .borderRadius(BubuRadius.button)
          .onClick(() => { this.archive(report.id); })
      } else {
        Text('✓ 已收进档案').fontSize(14).fontColor(BubuColor.success).width('100%').textAlign(TextAlign.Center)
      }
    }.width('100%')
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      if (!AIService.shared.isConfigured) {
        this.report = null;
        this.history = [];
        return;
      }
      this.report = (await AIService.shared.latestWeeklyReport()) ?? null;
      this.history = await AIService.shared.weeklyReportHistory();
      if (this.report) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await WeeklyReportNotifier.notifyIfNew(context, this.report!);
      }
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '周报暂时无法读取';
    } finally {
      this.loading = false;
    }
  }

  private async generate(): Promise<void> {
    if (this.operation.length > 0) return;
    this.operation = 'generating';
    this.errorText = '';
    try {
      this.report = await AIService.shared.generateWeeklyReport();
      this.history = await AIService.shared.weeklyReportHistory();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await WeeklyReportNotifier.notifyIfNew(context, this.report!);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '这次没有生成周报';
    } finally {
      this.operation = '';
    }
  }

  private async archive(id: string): Promise<void> {
    if (this.operation.length > 0) return;
    this.operation = 'archiving';
    this.errorText = '';
    try {
      this.report = await AIService.shared.archiveWeeklyReport(id);
      this.history = await AIService.shared.weeklyReportHistory();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '暂时无法归档周报';
    } finally {
      this.operation = '';
    }
  }

  private sourceFor(report: WeeklyReport, id: string): ArtifactSourceReference | undefined {
    return report.sourceRefs.find((source: ArtifactSourceReference): boolean => source.sourceId === id);
  }

  private sourceTitle(source: ArtifactSourceReference): string {
    const date = source.happenedAt.length >= 10 ? source.happenedAt.substring(0, 10) : source.happenedAt;
    return `${date} · ${source.title || source.excerpt}`;
  }

  private async openSource(source: ArtifactSourceReference): Promise<void> {
    const entry = (await AppDatabase.shared.fetchEntries(true)).find((item: Entry): boolean => item.id === source.localId);
    if (entry) this.selectedEntry = entry;
  }

  private weekText(report: WeeklyReport): string {
    return `${report.weekStart.substring(0, 10)} — ${report.weekEnd.substring(0, 10)}`;
  }
}

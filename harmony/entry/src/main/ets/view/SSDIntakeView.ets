import { AIService, SSDIntakeCandidate } from '../services/AIService';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';

// 家庭 mini / 移动硬盘生成的候选必须回到手机确认；忽略和确认都走服务端幂等批次接口。
@Component
export struct SSDIntakeView {
  onClose: () => void = () => {};
  @State private candidates: SSDIntakeCandidate[] = [];
  @State private editedDates: Map<string, number> = new Map();
  @State private loading: boolean = false;
  @State private workingId: string = '';
  @State private errorText: string = '';

  aboutToAppear(): void { this.reload(); }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回').backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown).onClick(this.onClose)
        Text('移动硬盘候选').fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 14 }) {
          Text('这里只显示家庭 mini 已整理好的候选。你确认后才会进入正式时光，忽略不会删除原文件。')
            .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
            .padding(14).backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)

          if (this.loading) {
            LoadingProgress().width(36).height(36).color(BubuColor.primary)
          } else if (this.candidates.length === 0) {
            Text('暂时没有待确认候选').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
              .padding(28)
          }

          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(13).fontColor(BubuColor.danger).width('100%')
          }

          ForEach(this.candidates, (candidate: SSDIntakeCandidate) => {
            this.candidateCard(candidate)
          }, (candidate: SSDIntakeCandidate): string => candidate.id)
        }.width('100%').padding(16)
      }.layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  private candidateCard(candidate: SSDIntakeCandidate) {
    Column({ space: 10 }) {
      Text(`${candidate.items.length} 个照片或视频`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
      Text(candidate.items.slice(0, 3).map(item => item.fileName).join('、'))
        .fontSize(12).fontColor(BubuColor.secondaryText).width('100%').maxLines(2)
      if (candidate.items.length > 3) {
        Text(`另有 ${candidate.items.length - 3} 个素材`).fontSize(12).fontColor(BubuColor.secondaryText).width('100%')
      }
      Row() {
        Text('发生时间').fontSize(13).fontColor(BubuColor.secondaryText)
        Blank()
        Text(this.dateText(this.dateFor(candidate)))
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
          .onClick(() => { this.pickDate(candidate); })
      }.width('100%')
      if (candidate.entry.captureTimeSources.includes('file-modified-fallback')) {
        Text('未读到内嵌拍摄时间，当前日期按文件时间推测，请核对。')
          .fontSize(12).fontColor(BubuColor.warning).width('100%')
      }
      Row({ space: 10 }) {
        Button('忽略').layoutWeight(1).height(48)
          .enabled(this.workingId.length === 0).backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
          .onClick(() => { this.cancel(candidate); })
        Button(this.workingId === candidate.id ? '处理中…' : '确认收进').layoutWeight(1).height(48)
          .enabled(this.workingId.length === 0).backgroundColor(BubuColor.primary).fontColor(Color.White)
          .onClick(() => { this.confirm(candidate); })
      }.width('100%')
    }.width('100%').padding(14).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  private async reload(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.errorText = '';
    try {
      const values = await AIService.shared.intakeCandidates();
      const dates = new Map<string, number>();
      for (const candidate of values) dates.set(candidate.id, this.parseDate(candidate.entry.happenedAt));
      this.editedDates = dates;
      this.candidates = values;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '候选暂时没能加载';
    } finally {
      this.loading = false;
    }
  }

  private pickDate(candidate: SSDIntakeCandidate): void {
    const current = this.dateFor(candidate);
    this.getUIContext().showDatePickerDialog({
      start: new Date(2015, 0, 1),
      end: new Date(),
      selected: new Date(current),
      onDateAccept: (value: Date) => {
        const previous = new Date(current);
        value.setHours(previous.getHours(), previous.getMinutes(), 0, 0);
        const next = new Map(this.editedDates);
        next.set(candidate.id, value.getTime());
        this.editedDates = next;
      }
    });
  }

  private async confirm(candidate: SSDIntakeCandidate): Promise<void> {
    if (this.workingId.length > 0) return;
    this.workingId = candidate.id;
    this.errorText = '';
    try {
      await AIService.shared.updateIntakeCandidate(candidate.id, this.dateFor(candidate));
      await AIService.shared.confirmIntakeCandidate(candidate.id);
      this.candidates = this.candidates.filter(item => item.id !== candidate.id);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '这段时光暂时没能收进';
    } finally {
      this.workingId = '';
    }
  }

  private async cancel(candidate: SSDIntakeCandidate): Promise<void> {
    if (this.workingId.length > 0) return;
    this.workingId = candidate.id;
    this.errorText = '';
    try {
      await AIService.shared.cancelIntakeCandidate(candidate.id);
      this.candidates = this.candidates.filter(item => item.id !== candidate.id);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '候选暂时没能忽略';
    } finally {
      this.workingId = '';
    }
  }

  private dateFor(candidate: SSDIntakeCandidate): number {
    return this.editedDates.get(candidate.id) ?? this.parseDate(candidate.entry.happenedAt);
  }

  private parseDate(value: string): number {
    const parsed = new Date(value).getTime();
    return parsed === parsed ? parsed : Date.now();
  }

  private dateText(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}.${date.getMonth() + 1}.${date.getDate()} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
}

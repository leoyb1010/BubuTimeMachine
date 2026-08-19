import { Entry, GrowthMeasurement } from '../models/Models';
import { QAContextRecord } from '../models/AIArtifacts';
import { QAMemoryFact, retrieveQAContexts } from '../models/QARetrieval';
import { AppDatabase } from '../data/AppDatabase';
import { AIService } from '../services/AIService';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { EntryDetailView } from './EntryDetailView';

interface QASource {
  id: string;
  dateText: string;
  snippet: string;
}

interface QAMessage {
  id: string;
  isUser: boolean;
  text: string;
  sources: QASource[];
}

@Component
export struct BubuQAView {
  onBack: () => void = () => {};

  @State input: string = '';
  @State messages: QAMessage[] = [];
  @State thinking: boolean = false;
  @State selectedEntry: Entry | null = null;

  private samples: string[] = [
    '第一次叫妈妈是什么时候？',
    '最近有什么新变化？',
    '去年今天在干嘛？',
    '最开心的一天是哪天？'
  ];

  build() {
    if (this.selectedEntry) {
      Column() {
        this.header('记录出处', () => { this.selectedEntry = null; })
        EntryDetailView({ entry: this.selectedEntry!, onDismiss: () => { this.selectedEntry = null; } })
          .layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.background)
    } else {
      Column() {
        this.header('问问布布', this.onBack)
        Scroll() {
          Column({ space: 12 }) {
            if (this.messages.length === 0) this.intro()
            ForEach(this.messages, (message: QAMessage) => {
              this.messageBubble(message)
            }, (message: QAMessage): string => message.id)
            if (this.thinking) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color(BubuColor.primary)
                Text('正在翻布布的时光…').fontSize(14).fontColor(BubuColor.secondaryText)
              }
              .width('100%').padding(14)
            }
          }.width('100%').padding(16)
        }.layoutWeight(1)

        Row({ space: 10 }) {
          TextInput({ text: $$this.input, placeholder: '问问关于布布的…' })
            .layoutWeight(1).height(48)
            .backgroundColor(BubuColor.softFill).borderRadius(BubuRadius.small)
          Button('发送')
            .height(48).width(72)
            .enabled(this.input.trim().length > 0 && !this.thinking)
            .backgroundColor(this.input.trim().length > 0 && !this.thinking ? BubuColor.primary : BubuColor.softFill)
            .fontColor(this.input.trim().length > 0 && !this.thinking ? Color.White : BubuColor.secondaryText)
            .borderRadius(BubuRadius.button)
            .onClick(() => { this.ask(this.input); })
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 12 })
        .backgroundColor(BubuColor.card)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.background)
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
    }
    .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 8 })
  }

  @Builder
  private intro() {
    Column({ space: 12 }) {
      Text('关于布布的成长，问我都行')
        .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text('我只根据你记录过的内容回答，并把真正用到的出处放在答案下面。')
        .fontSize(14).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.samples, (sample: string) => {
          Button(sample)
            .height(44).margin(4)
            .backgroundColor('#1FF28C9E').fontColor(BubuColor.primary)
            .borderRadius(22)
            .onClick(() => { this.ask(sample); })
        }, (sample: string): string => sample)
      }.width('100%')
    }
    .width('100%').padding(18)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  @Builder
  private messageBubble(message: QAMessage) {
    Row() {
      if (message.isUser) Blank().width(42)
      Column({ space: 8 }) {
        Text(message.text)
          .fontSize(15)
          .fontColor(message.isUser ? Color.White : BubuColor.warmBrown)
          .width('100%')
        ForEach(message.sources, (source: QASource) => {
          Button(`${source.dateText} · ${source.snippet}`)
            .height(44).width('100%')
            .backgroundColor(message.isUser ? '#2EFFFFFF' : BubuColor.softFill)
            .fontColor(message.isUser ? Color.White : BubuColor.secondaryText)
            .borderRadius(12)
            .onClick(() => { this.openSource(source.id); })
        }, (source: QASource): string => source.id)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1).padding(14)
      .backgroundColor(message.isUser ? BubuColor.primary : BubuColor.card)
      .borderRadius(BubuRadius.small)
      if (!message.isUser) Blank().width(42)
    }.width('100%')
  }

  private async ask(raw: string): Promise<void> {
    const question = raw.trim();
    if (question.length === 0 || this.thinking) return;
    this.input = '';
    this.messages = this.messages.concat([this.message(true, question, [])]);
    this.thinking = true;
    try {
      if (!AIService.shared.isConfigured) throw new Error('请先在设置里连接家里的 AI 服务');
      const contexts = await this.retrieve(question);
      const answer = await AIService.shared.ask(question, '布布', contexts);
      const sources = contexts.filter((context: QAContextRecord): boolean => answer.usedIds.includes(context.id))
        .slice(0, 3).map((context: QAContextRecord): QASource => ({
          id: context.id,
          dateText: context.dateText,
          snippet: context.text.substring(0, 24)
        }));
      this.messages = this.messages.concat([this.message(false, answer.answer, sources)]);
    } catch (e) {
      const text = e instanceof Error ? e.message : '现在暂时回答不了，请稍后再试';
      this.messages = this.messages.concat([this.message(false, text, [])]);
    } finally {
      this.thinking = false;
    }
  }

  private async retrieve(question: string): Promise<QAContextRecord[]> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    const facts: QAMemoryFact[] = [];
    for (const entry of await AppDatabase.shared.fetchEntries(false)) {
      const notes: string[] = [];
      if (entry.title) notes.push(entry.title);
      if (entry.note) notes.push(entry.note);
      if (entry.firstPersonNote) notes.push(entry.firstPersonNote);
      for (const voice of await AppDatabase.shared.fetchVoiceForEntry(entry.id)) {
        if (voice.transcript) notes.push(voice.transcript);
      }
      facts.push(this.fact(entry.id, entry.happenedAt, notes.join(' '), profile?.birthday));
    }
    for (const milestone of await AppDatabase.shared.fetchMilestones()) {
      if (milestone.happenedAt === undefined) continue;
      facts.push(this.fact(milestone.id, milestone.happenedAt,
        `里程碑：${milestone.title} ${milestone.detail ?? ''}`, profile?.birthday));
    }
    for (const growth of await AppDatabase.shared.fetchGrowth()) {
      facts.push(this.fact(growth.id, growth.measuredAt, this.growthText(growth), profile?.birthday));
    }
    return retrieveQAContexts(question, facts);
  }

  private fact(id: string, happenedAt: number, text: string, birthday?: number): QAMemoryFact {
    return {
      id, happenedAt, text,
      dateText: new Date(happenedAt).toLocaleDateString('zh-CN'),
      ageText: birthday === undefined ? '' : AgeCalculator.ageDescription(birthday, happenedAt)
    };
  }

  private growthText(growth: GrowthMeasurement): string {
    const parts: string[] = ['成长测量'];
    if (growth.heightCm !== undefined) parts.push(`身高 ${growth.heightCm}cm`);
    if (growth.weightKg !== undefined) parts.push(`体重 ${growth.weightKg}kg`);
    if (growth.headCircumferenceCm !== undefined) parts.push(`头围 ${growth.headCircumferenceCm}cm`);
    return parts.join(' · ');
  }

  private message(isUser: boolean, text: string, sources: QASource[]): QAMessage {
    return { id: `${Date.now()}-${this.messages.length}`, isUser, text, sources };
  }

  private async openSource(id: string): Promise<void> {
    const entry = (await AppDatabase.shared.fetchEntries(true)).find((item: Entry): boolean => item.id === id);
    if (entry) this.selectedEntry = entry;
  }
}

import { Entry, Comment } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { AIService } from '../services/AIService';
import { ServerConfig } from '../services/ServerConfig';
import { ReactionUtil } from './Reaction';

// MARK: - 家人合奏（对照 iOS Features/AIStudio/FamilyEnsembleView.swift）
// 找出有多位家人补充（Comment）的记录，把多视角「合成」成一段完整的故事。

// 一条候选记录及其补充（iOS 用 entry.comments 关系，HarmonyOS 需单独查 Comment 表预取）。
interface EnsembleCandidate {
  entry: Entry;
  comments: Comment[];
}

@Component
export struct FamilyEnsembleView {
  onBack: () => void = () => {};

  @State private candidates: EnsembleCandidate[] = [];
  @State private selectedId: string = '';
  @State private generating: boolean = false;
  @State private story: string = '';
  @State private displayed: string = '';
  @State private fallbackHint: string = '';
  private generationToken: number = 0;

  private theme: string = BubuColor.primary;

  aboutToAppear(): void { this.reload(); }

  // 至少有一条补充才值得合奏（对照 iOS candidates: !comments.isEmpty）。
  private async reload(): Promise<void> {
    const entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    const out: EnsembleCandidate[] = [];
    for (const e of entries) {
      const comments = (await AppDatabase.shared.fetchCommentsForEntry(e.id))
        .filter((comment: Comment): boolean => !ReactionUtil.isReaction(comment));
      if (comments.length > 0) out.push({ entry: e, comments: comments });
    }
    this.candidates = out;
  }

  private selectedCandidate(): EnsembleCandidate | undefined {
    return this.candidates.find((c: EnsembleCandidate): boolean => c.entry.id === this.selectedId);
  }

  build() {
    Column() {
      this.navBar()
      Scroll() {
        Column({ space: 20 }) {
          Text('当爸爸、妈妈、姥姥都为同一刻留下只言片语，AI 把它们编织成一个完整的故事。')
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.secondaryText)
            .width('100%')

          if (this.candidates.length === 0) {
            this.emptyState()
          } else {
            this.picker()
            if (this.selectedCandidate() !== undefined) {
              this.ensembleArea(this.selectedCandidate()!)
            }
          }
        }
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .backgroundColor(BubuColor.background)
    .width('100%')
    .height('100%')
  }

  @Builder
  navBar() {
    Row({ space: 12 }) {
      Text('‹ 返回')
        .fontSize(BubuFont.body)
        .fontColor(this.theme)
        .onClick(() => { this.onBack(); })
      Text('家人合奏')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  // 空态（对照 iOS ContentUnavailableView「还没有合奏素材」）。
  @Builder
  emptyState() {
    Column({ space: 12 }) {
      Text('👨‍👩‍👧').fontSize(56)
      Text('还没有合奏素材')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text('在某条记录的详情页里，让家人各自「补充」几句，就能在这里合成。')
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(260)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  picker() {
    Column({ space: 10 }) {
      Text('选一个有家人补充的瞬间')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
        .width('100%')
      ForEach(this.candidates.slice(0, 8), (c: EnsembleCandidate) => {
        Row() {
          Column({ space: 4 }) {
            Text(BubuDateFormat.shortDate(new Date(c.entry.happenedAt)))
              .fontSize(11)
              .fontColor(BubuColor.secondaryText)
            Text(c.entry.note !== undefined && c.entry.note.length > 0 ? c.entry.note : '（无文字）')
              .fontSize(BubuFont.body)
              .fontColor(BubuColor.warmBrown)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 视角数 = 补充数 + 原记录作者（对照 iOS comments.count + 1）。
          Text(`${c.comments.length + 1} 个视角`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(BubuColor.card)
        .borderRadius(BubuRadius.small)
        .border({ width: 2, color: this.selectedId === c.entry.id ? this.theme : 'transparent' })
        .onClick(() => {
          this.selectedId = c.entry.id;
          this.story = '';
          this.displayed = '';
          this.fallbackHint = '';
          this.generationToken += 1;
          this.generating = false;
        })
      }, (c: EnsembleCandidate) => c.entry.id)
    }
    .width('100%')
  }

  @Builder
  ensembleArea(c: EnsembleCandidate) {
    Column({ space: 14 }) {
      // 多视角原料（对照 iOS voiceLine）。
      Column({ space: 8 }) {
        this.voiceLine(c.entry.authorRole, c.entry.note !== undefined && c.entry.note.length > 0 ? c.entry.note : '（记录了这一刻）')
        ForEach(this.sortedComments(c.comments), (cm: Comment) => {
          this.voiceLine(cm.authorRole, cm.text !== undefined && cm.text.length > 0 ? cm.text : '（一段语音）')
        }, (cm: Comment) => cm.id)
      }
      .width('100%')

      // 合成按钮（对照 iOS「合成完整的故事」/「正在合奏……」）。
      Row({ space: 8 }) {
        if (this.generating) {
          LoadingProgress().width(22).height(22).color('#FFFFFF')
        } else {
          Text('🪄').fontSize(18)
        }
        Text(this.generating ? '正在合奏……' : '合成完整的故事')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(54)
      .backgroundColor(this.theme)
      .borderRadius(27)
      .opacity(this.generating ? 0.7 : 1.0)
      .onClick(() => { if (!this.generating) { this.synthesize(c); } })

      if (this.displayed.length > 0) {
        Text(this.displayed)
          .fontSize(18)
          .fontColor(BubuColor.warmBrown)
          .lineHeight(28)
          .width('100%')
          .padding(16)
          .backgroundColor('#12F28C9E')
          .borderRadius(BubuRadius.card)
      }
      if (this.fallbackHint.length > 0) {
        Text(this.fallbackHint).fontSize(11).fontColor(BubuColor.secondaryText).width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  voiceLine(role: string, text: string) {
    Row({ space: 10 }) {
      Text(role)
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme)
        .width(44)
      Text(text)
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.warmBrown)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  private sortedComments(comments: Comment[]): Comment[] {
    return comments.slice().sort((a: Comment, b: Comment): number => a.createdAt - b.createdAt);
  }

  // 配置真实 AI 时复用 rewrite-first-person 织成第三人称故事；失败才回落确定性本地模板。
  private async synthesize(c: EnsembleCandidate): Promise<void> {
    const token = this.generationToken + 1;
    this.generationToken = token;
    this.generating = true;
    this.displayed = '';
    this.fallbackHint = '';
    const perspectives: string[] = [];
    perspectives.push(`${c.entry.authorRole}说：${c.entry.note !== undefined && c.entry.note.length > 0 ? c.entry.note : '记录了这一刻'}`);
    for (const cm of this.sortedComments(c.comments)) {
      if (cm.text !== undefined && cm.text.length > 0) {
        perspectives.push(`${cm.authorRole}说：${cm.text}`);
      }
    }
    if (AIService.shared.isConfigured) {
      try {
        const prompt = `请以第三人称、150字左右，把家人对同一瞬间的多视角记录织成一段温暖完整的小故事，保留每个人的称谓；不要添加原文没有的事实。\n日期：${BubuDateFormat.longDate(new Date(c.entry.happenedAt))}\n${perspectives.join('\n')}`;
        const woven = (await AIService.shared.rewriteFirstPerson(prompt, ServerConfig.shared.childName)).trim();
        if (woven.length > 0 && token === this.generationToken) {
          this.story = woven;
          await this.typewriter(this.story, token);
          this.generating = false;
          return;
        }
      } catch (e) {}
    }
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 400));
    if (token !== this.generationToken) return;
    this.fallbackHint = AIService.shared.isConfigured ? 'AI 暂时没连上，下面是本机简易合奏。' : '当前使用本机简易合奏。';
    this.story = `那是 ${BubuDateFormat.longDate(new Date(c.entry.happenedAt))}。\n${perspectives.join('；')}。\n同一个瞬间，在每个人心里留下了不一样的温柔。这就是属于${ServerConfig.shared.childName}的、被全家人一起记住的一天。`;
    await this.typewriter(this.story, token);
    this.generating = false;
  }

  private async typewriter(text: string, token: number): Promise<void> {
    this.displayed = '';
    const chars = Array.from(text);
    for (const ch of chars) {
      if (token !== this.generationToken) return;
      this.displayed += ch;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 22));
    }
  }
}

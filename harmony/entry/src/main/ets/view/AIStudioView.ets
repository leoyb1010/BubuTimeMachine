import { Entry, HealthRecord, Milestone, FamilyMember, TimeCapsule, ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// MARK: - 布布的故事 / AI Studio（对照 iOS AIStudioHomeView）
// 入口卡：成长电影 / 第一人称日记 / 成长报告。对接现有 FastAPI（AIService）。
interface StudioEntry {
  emoji: string;
  title: string;
  subtitle: string;
  kind: string;
}

const STUDIO_ITEMS: StudioEntry[] = [
  { emoji: '🎬', title: '成长电影', subtitle: '把这一年的瞬间拼成一部小电影', kind: 'movie' },
  { emoji: '📖', title: '第一人称日记', subtitle: '用布布的口吻，把记录改写成日记', kind: 'diary' },
  { emoji: '📊', title: '成长报告', subtitle: '阶段性回顾布布的点滴变化', kind: 'report' },
  { emoji: '👨‍👩‍👧', title: '家庭合奏', subtitle: '把全家的多视角补充汇成一段故事', kind: 'ensemble' }
];

@Component
export struct AIStudioView {
  @State entries: Entry[] = [];
  @State healthRecords: HealthRecord[] = [];
  @State milestones: Milestone[] = [];
  @State members: FamilyMember[] = [];
  @State capsules: TimeCapsule[] = [];
  @State profile: ChildProfile | null = null;
  @State photoCount: number = 0;
  @State selectedKind: string = '';
  @State generatedTitle: string = '';
  @State generatedBody: string = '';

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    this.healthRecords = await AppDatabase.shared.fetchHealth() ?? [];
    this.milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    this.members = await AppDatabase.shared.fetchMembers() ?? [];
    this.capsules = await AppDatabase.shared.fetchCapsules() ?? [];
    this.photoCount = (await AppDatabase.shared.fetchAllPhotos() ?? []).length;
  }

  build() {
    if (this.selectedKind.length > 0) {
      this.detailPanel()
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 16 }) {
        Text('布布的故事')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
        Text('由 AI 把布布的点滴，讲成值得收藏的故事')
          .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')

        ForEach(STUDIO_ITEMS, (it: StudioEntry) => {
          Row({ space: 14 }) {
            Text(it.emoji).fontSize(34)
            Column() {
              Text(it.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
              Text(it.subtitle).fontSize(12).fontColor(BubuColor.secondaryText).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(BubuColor.secondaryText)
          }
          .width('100%').padding(16)
          .backgroundColor(BubuColor.card).borderRadius(16)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => { this.openStudioItem(it); })
        }, (it: StudioEntry) => it.title)

        Text('需在设置里连上家里的 AI 服务后生成')
          .fontSize(11).fontColor(BubuColor.secondaryText).margin({ top: 8 })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  @Builder
  detailPanel() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3')
            .fontColor(BubuColor.warmBrown)
            .onClick(() => { this.selectedKind = ''; })
          Text(this.currentTitle())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }.width('100%')

        Column({ space: 10 }) {
          Text(this.currentEmoji()).fontSize(56)
          Text(this.generatedTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.materialSummary())
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(18)
        .backgroundColor(BubuColor.card)
        .borderRadius(18)

        Text(this.generatedBody)
          .fontSize(16)
          .fontColor(BubuColor.warmBrown)
          .lineHeight(28)
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFFCC')
          .borderRadius(18)

        Button('重新生成预览')
          .width('100%')
          .backgroundColor(BubuColor.primary)
          .onClick(() => {
            this.generatePreview(this.selectedKind);
            promptAction.showToast({ message: '已重新整理预览' });
          })
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  private openStudioItem(it: StudioEntry): void {
    this.selectedKind = it.kind;
    this.generatePreview(it.kind);
  }

  private currentItem(): StudioEntry {
    for (const it of STUDIO_ITEMS) {
      if (it.kind === this.selectedKind) return it;
    }
    return STUDIO_ITEMS[0];
  }

  private currentTitle(): string {
    return this.currentItem().title;
  }

  private currentEmoji(): string {
    return this.currentItem().emoji;
  }

  private materialSummary(): string {
    return `${this.entryList().length} 条记录 · ${this.photoCount} 张照片 · ${this.healthList().length} 条健康记录 · ${this.achievedMilestones().length} 个里程碑`;
  }

  private entryList(): Entry[] {
    return this.entries ?? [];
  }

  private healthList(): HealthRecord[] {
    return this.healthRecords ?? [];
  }

  private milestoneList(): Milestone[] {
    return this.milestones ?? [];
  }

  private memberList(): FamilyMember[] {
    return this.members ?? [];
  }

  private capsuleList(): TimeCapsule[] {
    return this.capsules ?? [];
  }

  private achievedMilestones(): Milestone[] {
    return this.milestoneList().filter(m => m.happenedAt !== undefined && m.happenedAt !== null);
  }

  private latestNote(): string {
    for (const e of this.entryList()) {
      if (e.note && e.note.length > 0) return e.note;
    }
    return '';
  }

  private childName(): string {
    return this.profile ? this.profile!.name : '布布';
  }

  private generatePreview(kind: string): void {
    const child = this.childName();
    if (kind === 'movie') {
      this.generatedTitle = this.photoCount > 0 ? '电影草稿素材已就绪' : '先补几张照片再生成电影';
      this.generatedBody = this.photoCount > 0
        ? `已按时间线找到 ${this.photoCount} 张照片和 ${this.entryList().length} 条记录。下一步可以把照片按月份串起来，片头使用「${child} 的成长电影」，字幕从记录文字里提取。`
        : `成长电影需要真实照片做素材。先回到「记录此刻」加照片，照片墙里出现素材后，这里就能生成电影草稿。`;
      return;
    }

    if (kind === 'diary') {
      const note = this.latestNote();
      this.generatedTitle = note.length > 0 ? '布布的日记预览' : '还没有可改写的记录';
      this.generatedBody = note.length > 0
        ? `我是${child}。今天家人帮我记下了这一刻：「${note}」。等我长大再看见这句话，就会知道这一天也被好好收藏着。`
        : `先在「记录此刻」写下一句父母视角的话，这里会把它整理成${child}的第一人称日记。`;
      return;
    }

    if (kind === 'report') {
      this.generatedTitle = '成长报告预览';
      this.generatedBody = `这份档案目前收到了 ${this.entryList().length} 条瞬间、${this.photoCount} 张照片、${this.healthList().length} 条照护记录、${this.achievedMilestones().length} 个已点亮里程碑和 ${this.capsuleList().length} 封时间胶囊。这里先做整理，不替${child}下发育结论。`;
      return;
    }

    this.generatedTitle = this.memberList().length > 0 ? '家庭合奏预览' : '先添加家庭成员';
    this.generatedBody = this.memberList().length > 0
      ? `已经有 ${this.memberList().length} 位家人加入档案。家庭合奏会把不同家人留下的记录、补充和时间线放在一起，整理成一段完整故事。`
      : `去首页右上角设置里添加家庭成员后，这里会按爸爸、妈妈、姥姥等不同视角整理故事。`;
  }
}

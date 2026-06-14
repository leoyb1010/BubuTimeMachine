// MARK: - 成长之声（声纹长卷，对照 iOS Features/Settings/VoiceArchiveView.swift）
// 按「岁」归档布布的声音 + 家人对她说的话。录制时按布布生日自动算 ageYears 归档。
// iOS 用 Menu + sheet 录制；ArkUI 用顶部「录布布的声音 / 家人对她说」两个入口 + 内嵌录制面板。

import { util } from '@kit.ArkTS';
import { AppDatabase } from '../data/AppDatabase';
import { VoiceMemo, VoiceMemoKind, ChildProfile } from '../models/Models';
import { SyncState } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius, BubuSpacing } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { ThemeManager } from '../theme/ThemeManager';
import { VoiceRecorderBar, VoicePlayerBubble } from '../components/VoiceComponents';
import { promptAction } from '@kit.ArkUI';

// 按岁分组的一段（age 降序）。
interface AgeGroup {
  age: number;
  memos: VoiceMemo[];
}

@Component
export struct VoiceArchiveView {
  onClose?: () => void;

  @State private memos: VoiceMemo[] = [];
  @State private profile: ChildProfile | null = null;
  @State private showRecorder: boolean = false;
  @State private recordKind: string = VoiceMemoKind.childVoice;
  // 录制结果暂存。
  @State private pendingFile: string = '';
  @State private pendingDuration: number = 0;
  @State private pendingWaveform: number[] = [];

  private get theme(): string { return ThemeManager.shared.theme.primary; }

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.memos = (await AppDatabase.shared.fetchVoiceMemos()) ?? [];
  }

  // 按 ageYears 分组，组内保留录制时间降序（fetch 已降序），组按 age 降序。
  private grouped(): AgeGroup[] {
    const dict = new Map<number, VoiceMemo[]>();
    for (const m of this.memos) {
      const age = m.ageYears ?? 0;
      const arr = dict.get(age) ?? [];
      arr.push(m);
      dict.set(age, arr);
    }
    const groups: AgeGroup[] = [];
    dict.forEach((memos: VoiceMemo[], age: number) => { groups.push({ age, memos }); });
    groups.sort((a: AgeGroup, b: AgeGroup): number => b.age - a.age);
    return groups;
  }

  build() {
    if (this.showRecorder) {
      this.recorderPanel()
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Column() {
      Row({ space: 12 }) {
        if (this.onClose) {
          Button('返回')
            .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { this.onClose!(); })
        }
        Text('成长之声').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text('🎙️+').fontSize(22)
          .onClick(() => { this.openRecorder(VoiceMemoKind.childVoice); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 录制入口（对照 iOS toolbar Menu 两项）。
      Row({ space: 10 }) {
        Button('录布布的声音')
          .layoutWeight(1).backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
          .onClick(() => { this.openRecorder(VoiceMemoKind.childVoice); })
        Button('家人对她说')
          .layoutWeight(1).backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
          .onClick(() => { this.openRecorder(VoiceMemoKind.familyVoice); })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 8 })

      if (this.memos.length === 0) {
        this.emptyState()
      } else {
        Scroll() {
          Column({ space: BubuSpacing.section }) {
            Text('把布布的咿呀、第一声「妈妈」、家人想对她说的话，按一岁一岁收好。多年以后，听得见时间。')
              .fontSize(BubuFont.body).fontColor(BubuColor.secondaryText).width('100%')
            ForEach(this.grouped(), (group: AgeGroup) => {
              this.yearSection(group)
            }, (group: AgeGroup) => group.age.toString())
          }
          .padding(16).width('100%')
        }
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  yearSection(group: AgeGroup) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(group.age === 0 ? '0 岁' : `${group.age} 岁`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.theme)
        Divider().color(this.theme).opacity(0.2).layoutWeight(1)
      }
      .width('100%')
      ForEach(group.memos, (memo: VoiceMemo) => {
        this.memoRow(memo)
      }, (memo: VoiceMemo) => memo.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  memoRow(memo: VoiceMemo) {
    Column({ space: 8 }) {
      Row() {
        Text(memo.kindRaw === VoiceMemoKind.childVoice ? '🗣️ 布布的声音' : '💗 家人对她说')
          .fontSize(BubuFont.caption).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        Blank()
        Text(BubuDateFormat.shortDate(new Date(memo.recordedAt)))
          .fontSize(11).fontColor(BubuColor.secondaryText)
      }
      .width('100%')
      if (memo.localFileName !== undefined && memo.localFileName !== null) {
        VoicePlayerBubble({
          fileName: memo.localFileName,
          duration: memo.durationSeconds ?? 0,
          waveform: [],
          tint: this.theme
        })
      }
      if (memo.transcript !== undefined && memo.transcript !== null && memo.transcript.length > 0) {
        Text(memo.transcript)
          .fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText).fontStyle(FontStyle.Italic)
          .width('100%')
      }
    }
    .width('100%').padding(16)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  emptyState() {
    Column({ space: 18 }) {
      Text('🎵').fontSize(64)
      Text('还没有声音').fontSize(BubuFont.title).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text('点上面的按钮，录下布布此刻的声音。')
        .fontSize(BubuFont.body).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(40)
  }

  // MARK: 录制面板（对照 iOS VoiceMemoRecorderSheet）

  @Builder
  recorderPanel() {
    Column({ space: 24 }) {
      Row({ space: 12 }) {
        Button('取消')
          .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
          .onClick(() => { this.closeRecorder(); })
        Text('成长之声').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Button('收好')
          .backgroundColor(BubuColor.primary)
          .enabled(this.pendingFile.length > 0)
          .onClick(() => { this.save(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Text(this.recordKind === VoiceMemoKind.childVoice ? '录下布布的声音' : '对布布说点什么')
        .fontSize(BubuFont.title).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)

      if (this.pendingFile.length > 0) {
        VoicePlayerBubble({
          fileName: this.pendingFile,
          duration: this.pendingDuration,
          waveform: this.pendingWaveform,
          tint: this.theme
        })
      } else {
        VoiceRecorderBar({
          tint: this.theme,
          onFinished: (fileName: string, duration: number, waveform: number[]) => {
            this.pendingFile = fileName;
            this.pendingDuration = duration;
            this.pendingWaveform = waveform;
          }
        })
      }
      Blank()
    }
    .width('100%').height('100%').padding({ left: 16, right: 16 }).backgroundColor(BubuColor.background)
  }

  private openRecorder(kind: string): void {
    this.recordKind = kind;
    this.pendingFile = '';
    this.pendingDuration = 0;
    this.pendingWaveform = [];
    this.showRecorder = true;
  }

  private closeRecorder(): void {
    this.showRecorder = false;
    this.pendingFile = '';
    this.pendingDuration = 0;
    this.pendingWaveform = [];
  }

  private async save(): Promise<void> {
    if (this.pendingFile.length === 0) return;
    const now = Date.now();
    const age = this.profile ? AgeCalculator.ageYears(this.profile.birthday, now) : 0;
    const memo: VoiceMemo = {
      id: util.generateRandomUUID(true),
      kindRaw: this.recordKind,
      localFileName: this.pendingFile,
      transcript: undefined,
      ageYears: age,
      recordedAt: now,
      durationSeconds: this.pendingDuration,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertVoiceMemo(memo);
    this.closeRecorder();
    await this.reload();
    promptAction.showToast({ message: '已收好 💛' });
  }
}

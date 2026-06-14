// MARK: - 全量档案导出（对照 iOS Features/Settings/ExportView.swift）
// 一键把布布的一切导出成可双击打开的网页 + 媒体包（index.html + data.json + media/）。
// iOS 打 zip 后调系统分享 sheet；HarmonyOS 暂无等价 zip+share，导出到 cacheDir 目录并展示路径。
// 导出完成写入 preferences 'bubu.lastExportAt'，供「备份健康度卡」判断是否过期（对照 iOS）。

import { preferences } from '@kit.ArkData';
import { AppDatabase } from '../data/AppDatabase';
import { Entry, Media, Milestone, VoiceMemo, HealthRecord, FirstTime, TimeCapsule, ChildProfile, Comment, VoiceNote } from '../models/Models';
import { MediaType, Mood, moodEmoji } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { healthKindMeta } from '../models/Enums';
import { HealthRecordKind } from '../models/Enums';
import {
  ArchiveExporter, ExportInput, EntrySnapshot, MediaSnapshot, VoiceSnapshot,
  CommentSnapshot, MilestoneSnapshot, VoiceMemoSnapshot, HealthRecordSnapshot,
  FirstTimeSnapshot, TimeCapsuleSnapshot
} from '../services/media/ArchiveExporter';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// 统计行数据。
interface CountRow { key: string; value: string; }

@Component
export struct ExportView {
  onClose?: () => void;

  @State private profile: ChildProfile | null = null;
  @State private entries: Entry[] = [];
  @State private milestones: Milestone[] = [];
  @State private voiceMemos: VoiceMemo[] = [];
  @State private healthRecords: HealthRecord[] = [];
  @State private firstTimes: FirstTime[] = [];
  @State private timeCapsules: TimeCapsule[] = [];
  // entryId → media / comments / voiceNotes（导出快照用）
  @State private mediaByEntry: Map<string, Media[]> = new Map();
  @State private commentsByEntry: Map<string, Comment[]> = new Map();
  @State private voicesByEntry: Map<string, VoiceNote[]> = new Map();

  @State private mediaCount: number = 0;
  @State private voiceCount: number = 0;
  @State private exporting: boolean = false;
  @State private resultPath: string = '';
  @State private errorText: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const db = AppDatabase.shared;
    this.profile = await db.fetchChildProfile();
    this.entries = (await db.fetchEntries(false)) ?? [];
    this.milestones = (await db.fetchMilestones()) ?? [];
    this.voiceMemos = (await db.fetchVoiceMemos()) ?? [];
    this.healthRecords = (await db.fetchHealth()) ?? [];
    this.firstTimes = (await db.fetchFirstTimes()) ?? [];
    this.timeCapsules = (await db.fetchCapsules()) ?? [];

    let media = 0;
    let voices = 0;
    for (const e of this.entries) {
      const m = (await db.fetchMediaForEntry(e.id)) ?? [];
      const c = (await db.fetchCommentsForEntry(e.id)) ?? [];
      const v = (await db.fetchVoiceForEntry(e.id)) ?? [];
      this.mediaByEntry.set(e.id, m);
      this.commentsByEntry.set(e.id, c);
      this.voicesByEntry.set(e.id, v);
      media += m.length;
      voices += v.length + c.filter((x: Comment) => x.voiceFileName !== undefined && x.voiceFileName !== null).length;
    }
    this.mediaCount = media;
    this.voiceCount = voices + this.voiceMemos.length;
  }

  // 已达成里程碑（happenedAt 非空，对照 iOS isAchieved）。
  private achievedMilestones(): Milestone[] {
    return this.milestones.filter((m: Milestone) => m.happenedAt !== undefined && m.happenedAt !== null);
  }

  private statRows(): CountRow[] {
    return [
      { key: '瞬间', value: `${this.entries.length} 个` },
      { key: '照片视频', value: `${this.mediaCount} 个` },
      { key: '声音', value: `${this.voiceCount} 段` },
      { key: '里程碑', value: `${this.achievedMilestones().length} 个` },
      { key: '健康/第一次/胶囊', value: `${this.healthRecords.length + this.firstTimes.length + this.timeCapsules.length} 项` }
    ];
  }

  build() {
    Column() {
      if (this.onClose) {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { this.onClose!(); })
          Text('全量导出').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }

      Scroll() {
        Column({ space: 24 }) {
          // hero
          Column({ space: 12 }) {
            Text('💾').fontSize(56)
            Text('布布的一生，装进一个文件夹')
              .fontSize(BubuFont.title).fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown).textAlign(TextAlign.Center)
            Text('导出成一个网页 + 全部媒体。双击 index.html 就能看，永久离线可读——即使将来 App 和服务器都不在了。')
              .fontSize(BubuFont.body).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
          }
          .width('100%').margin({ top: 12 })

          // 统计卡
          Column() {
            ForEach(this.statRows(), (r: CountRow, i: number) => {
              Row() {
                Text(r.key).fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
                Blank()
                Text(r.value).fontSize(BubuFont.body).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
              }
              .width('100%').padding({ top: 10, bottom: 10 })
              if (i < this.statRows().length - 1) {
                Divider().color(BubuColor.hairline)
              }
            }, (r: CountRow) => r.key)
          }
          .padding(16).width('100%')
          .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
          .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })

          // 导出按钮
          Button() {
            Row({ space: 8 }) {
              if (this.exporting) { LoadingProgress().width(20).height(20).color(Color.White) }
              Text(this.exporting ? '正在打包…' : '导出并分享')
                .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
          }
          .width('100%').height(54).backgroundColor(BubuColor.primary).borderRadius(27)
          .enabled(!this.exporting && this.profile !== null)
          .onClick(() => { this.runExport(); })

          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(BubuFont.caption).fontColor(BubuColor.danger).width('100%')
          }
          if (this.resultPath.length > 0) {
            Text(`已导出到：\n${this.resultPath}`)
              .fontSize(BubuFont.caption).fontColor(BubuColor.success).width('100%').textAlign(TextAlign.Center)
          }
        }
        .padding(16).width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  private async runExport(): Promise<void> {
    const profile = this.profile;
    if (!profile) return;
    this.exporting = true;
    this.errorText = '';
    this.resultPath = '';
    try {
      const snapshots: EntrySnapshot[] = this.entries.map((e: Entry): EntrySnapshot => {
        const media = (this.mediaByEntry.get(e.id) ?? []);
        const voices = (this.voicesByEntry.get(e.id) ?? []);
        const comments = (this.commentsByEntry.get(e.id) ?? []);
        const tags = new Set<string>();
        for (const m of media) { for (const t of m.aiTags) tags.add(t); }
        const mood: string | undefined = e.moodRaw !== undefined && e.moodRaw !== null
          ? moodEmoji(e.moodRaw as Mood) : undefined;
        const mediaSnaps: MediaSnapshot[] = [];
        for (const m of media) {
          if (m.localFileName) mediaSnaps.push({ fileName: m.localFileName, type: m.typeRaw });
        }
        const voiceSnaps: VoiceSnapshot[] = [];
        for (const v of voices) {
          if (v.localFileName) {
            voiceSnaps.push({ fileName: v.localFileName, duration: v.durationSeconds, authorRole: v.authorRole, transcript: v.transcript });
          }
        }
        const commentSnaps: CommentSnapshot[] = comments.map((c: Comment): CommentSnapshot => ({
          authorRole: c.authorRole, text: c.text, voiceFileName: c.voiceFileName,
          voiceDuration: c.voiceDuration, createdAt: c.createdAt
        }));
        const tagArr: string[] = [];
        tags.forEach((t: string) => tagArr.push(t));
        return {
          happenedAt: e.happenedAt, authorRole: e.authorRole, note: e.note,
          firstPersonNote: e.firstPersonNote, locationName: e.locationName,
          moodEmoji: mood,
          ageDescription: AgeCalculator.ageDescription(profile.birthday, e.happenedAt),
          media: mediaSnaps, voiceNotes: voiceSnaps, comments: commentSnaps, tags: tagArr
        };
      });

      const ms: MilestoneSnapshot[] = this.achievedMilestones().map((m: Milestone): MilestoneSnapshot => ({
        title: m.title, emoji: m.emoji, achieved: true, ageDescription: m.ageDescription
      }));
      const memoSnaps: VoiceMemoSnapshot[] = this.voiceMemos.map((m: VoiceMemo): VoiceMemoSnapshot => ({
        kind: m.kindRaw, fileName: m.localFileName, transcript: m.transcript,
        ageYears: m.ageYears, recordedAt: m.recordedAt, durationSeconds: m.durationSeconds
      }));
      const healthSnaps: HealthRecordSnapshot[] = this.healthRecords.map((r: HealthRecord): HealthRecordSnapshot => ({
        kind: healthKindMeta(r.kind as HealthRecordKind).title, title: r.title, detail: r.detail,
        recordedAt: r.recordedAt, amountText: r.amountText, reaction: r.reaction
      }));
      const firstTimeSnaps: FirstTimeSnapshot[] = this.firstTimes.map((f: FirstTime): FirstTimeSnapshot => ({
        what: f.what, happenedAt: f.happenedAt, confirmed: f.confirmedByParent
      }));
      const capsuleSnaps: TimeCapsuleSnapshot[] = this.timeCapsules.map((c: TimeCapsule): TimeCapsuleSnapshot => ({
        title: c.title, fromRole: c.fromRole, unlockAt: c.unlockAt, isLocked: c.isLocked, coverEmoji: c.coverEmoji
      }));

      const input: ExportInput = {
        childName: profile.name, birthday: profile.birthday,
        entries: snapshots, milestones: ms, voiceMemos: memoSnaps,
        healthRecords: healthSnaps, firstTimes: firstTimeSnaps, timeCapsules: capsuleSnaps
      };

      const folder = await ArchiveExporter.shared.export(input);
      this.resultPath = folder;
      // 记录导出时间戳（对照 iOS UserDefaults bubu.lastExportAt）。
      try {
        const store = preferences.getPreferencesSync(getContext(this), { name: 'bubu_widget' });
        store.putSync('bubu.lastExportAt', Math.floor(Date.now() / 1000));
        store.flush();
      } catch (e) {}
      promptAction.showToast({ message: '导出完成 💛' });
    } catch (e) {
      this.errorText = `导出失败：${e instanceof Error ? e.message : '请稍后再试'}`;
    }
    this.exporting = false;
  }
}

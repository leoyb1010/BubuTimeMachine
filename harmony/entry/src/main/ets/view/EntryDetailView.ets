import { Entry, ChildProfile, Media, Comment, VoiceNote, FeedEvent } from '../models/Models';
import { Mood, moodEmoji, MediaType, SyncState, FeedEventKind } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { MediaGalleryViewer } from '../components/MediaViewer';
import { VoicePlayerBubble, VoiceRecorderBar } from '../components/VoiceComponents';
import { MoodPicker } from '../components/MoodPicker';
import { CommentComposeSheet } from './CommentComposeSheet';
import { Reaction, ReactionUtil, ReactionSummary, ReactionRow, ReactionPicker, ALL_REACTIONS } from './Reaction';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';

// MARK: - 记录详情（对照 iOS Features/Timeline/EntryDetailView.swift）
// 已上传内容不再只读：可改文字/心情、追加语音、家人多视角补充、点亲亲。
// 大图网格（可全屏查看 / 编辑态可删）+ 反应条 + 元信息 + 备注 + 语音 + AI 标签 + 第一人称 + 家人合奏。
// 保留 prop 契约 { entry, onDismiss }，与 HomeView / TimelineView 调用一致。
@Component
export struct EntryDetailView {
  @Prop entry: Entry;
  // 关闭/删除后通知父级刷新。
  onDismiss?: () => void;

  @State private profile: ChildProfile | null = null;
  @State private media: Media[] = [];
  @State private comments: Comment[] = [];
  @State private voiceNotes: VoiceNote[] = [];

  @State private editing: boolean = false;
  // 编辑态本地草稿（保存时落库）。
  @State private draftNote: string = '';
  @State private draftMood: Mood | undefined = undefined;

  @State private showCommentSheet: boolean = false;
  @State private showReactionPicker: boolean = false;
  @State private viewingMediaID: string | null = null;

  aboutToAppear(): void { this.load(); }

  private theme(): string { return BubuColor.primary; }
  private myRole(): string { return ServerConfig.shared.currentRole; }

  private async load(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.media = await AppDatabase.shared.fetchMediaForEntry(this.entry.id);
    this.comments = await AppDatabase.shared.fetchCommentsForEntry(this.entry.id);
    this.voiceNotes = await AppDatabase.shared.fetchVoiceForEntry(this.entry.id);
    this.draftNote = this.entry.note ?? '';
    this.draftMood = this.entry.moodRaw as Mood | undefined;
  }

  // 排序后的媒体（对照 iOS sortedMedia，按 createdAt 升序）。
  private sortedMedia(): Media[] {
    return this.media.slice().sort((a: Media, b: Media) => a.createdAt - b.createdAt);
  }

  // 「此时 / 那时」前缀（对照 iOS timePerspectivePrefix）。
  private timePerspectivePrefix(): string {
    const months = (Date.now() - this.entry.happenedAt) / (30 * 86400000);
    return months <= 2 ? '此时' : '那时';
  }

  private reactionSummary(): ReactionSummary {
    return ReactionSummary.from(this.comments, this.myRole());
  }

  private realComments(): Comment[] {
    return this.comments
      .filter((c: Comment) => !ReactionUtil.isReaction(c))
      .sort((a: Comment, b: Comment) => a.createdAt - b.createdAt);
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 18 }) {
          this.ageBadge()
          this.mediaSection()
          this.reactionSection()
          if (this.editing) { this.appendPhotoButton() }
          this.metaSection()
          if ((this.entry.note !== undefined) || this.editing) { this.noteSection() }
          this.voiceNotesSection()
          this.tagsSection()
          this.firstPersonPlaceholder()
          this.familyEnsembleSection()
          this.toolbarRow()
          Blank().height(150)
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .backgroundColor(BubuColor.background)
      .width('100%').height('100%')

      // 反应选择条（对照 iOS popover ReactionPicker）。
      if (this.showReactionPicker) {
        Column() {
          ReactionPicker({
            current: this.reactionSummary().mine,
            onPick: (r: Reaction) => {
              this.toggleReaction(r);
              this.showReactionPicker = false;
            }
          })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
        .onClick(() => { this.showReactionPicker = false; })
      }

      // 家人合奏补充面板（对照 iOS .sheet CommentComposeSheet）。
      if (this.showCommentSheet) {
        CommentComposeSheet({
          entryId: this.entry.id,
          onClose: () => { this.showCommentSheet = false; },
          onSaved: () => { this.load(); }
        })
      }

      // 全屏媒体查看器（对照 iOS fullScreenCover MediaGalleryViewer）。
      if (this.viewingMediaID !== null) {
        MediaGalleryViewer({
          mediaItems: this.sortedMedia(),
          initialMediaID: this.viewingMediaID!,
          onDismiss: () => { this.viewingMediaID = null; }
        })
      }
    }
    .width('100%').height('100%')
  }

  // MARK: 顶部工具栏行（编辑/完成 + 删除，对照 iOS toolbar topBarTrailing）
  @Builder
  toolbarRow() {
    Row({ space: 12 }) {
      Button(this.editing ? '完成' : '编辑')
        .backgroundColor('#1AF28C9E').fontColor(this.theme()).fontWeight(FontWeight.Medium)
        .onClick(() => { this.toggleEditing(); })
      Blank()
      Button('🗑 删除记录')
        .backgroundColor('#FFE5E5').fontColor('#D9534F')
        .onClick(() => { this.confirmDelete(); })
    }
    .width('100%')
    .margin({ top: 8, bottom: 16 })
  }

  // MARK: 年龄角标（对照 iOS ageBadge）
  @Builder
  ageBadge() {
    if (this.profile) {
      Row({ space: 8 }) {
        Text('🎂').fontSize(16)
        Text(`${this.timePerspectivePrefix()}的布布 · ${AgeCalculator.ageDescription(this.profile!.birthday, this.entry.happenedAt)}`)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme())
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor('#1AF28C9E')
      .borderRadius(100)
    }
  }

  // MARK: 媒体网格（对照 iOS mediaSection：自适应两列；编辑态右上角删除）
  @Builder
  mediaSection() {
    if (this.media.length > 0) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.sortedMedia(), (m: Media) => {
          Stack() {
            MediaThumbnail({ media: m, cornerRadius: BubuRadius.card })
              .width('100%').aspectRatio(1)
              .onClick(() => { if (!this.editing) this.viewingMediaID = m.id; })
            if (this.editing) {
              Text('⊖')
                .fontSize(24).fontColor(Color.White)
                .backgroundColor('#D9534F')
                .borderRadius(14).width(28).height(28).textAlign(TextAlign.Center)
                .margin(6)
                .onClick(() => { this.deleteMedia(m); })
            }
          }
          .alignContent(Alignment.TopEnd)
          .width('50%')
          .padding(4)
        }, (m: Media) => m.id)
      }
      .width('100%')
    }
  }

  // MARK: 追加照片按钮（对照 iOS appendPhotoButton；切片无系统相册选择器，给占位提示）
  @Builder
  appendPhotoButton() {
    // NOTE: iOS 用 PhotosPicker 追加照片/视频。本切片未接入 HarmonyOS PhotoPicker，
    // 此处保留按钮形态与文案，点击提示后续可接 photoAccessHelper。
    Row({ space: 8 }) {
      Text('🖼').fontSize(18)
      Text('再添加照片/视频').fontSize(18).fontColor(this.theme())
    }
    .width('100%').justifyContent(FlexAlign.Center)
    .padding({ top: 12, bottom: 12 })
    .backgroundColor('#14F28C9E')
    .borderRadius(BubuRadius.small)
    .onClick(() => { promptAction.showToast({ message: '在手机上可从相册追加照片' }); })
  }

  // MARK: 亲一下（反应）条（对照 iOS reactionSection）
  @Builder
  reactionSection() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        Text(this.reactionSummary().mine === undefined ? '🤍' : '❤️').fontSize(15)
        Text(this.reactionSummary().mine === undefined ? '亲一下' : ReactionUtil.label(this.reactionSummary().mine!))
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.reactionSummary().mine === undefined ? BubuColor.secondaryText : this.theme())
      }
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.reactionSummary().mine === undefined ? '#0FF28C9E' : '#1FF28C9E')
      .borderRadius(100)
      .onClick(() => { this.showReactionPicker = true; })

      ReactionRow({ summary: this.reactionSummary() })
      Blank()
    }
    .width('100%')
  }

  // MARK: 元信息（对照 iOS metaSection：编辑态心情选择；只读态作者/心情/地点）
  @Builder
  metaSection() {
    if (this.editing) {
      Column({ space: 12 }) {
        // 发生时间只读展示（DatePicker 在切片中省略，保持时间不可误改）。
        Text(`发生时间 · ${BubuDateFormat.shortDateTime(new Date(this.entry.happenedAt))}`)
          .fontSize(15).fontColor(BubuColor.secondaryText)
        MoodPicker({
          selection: this.draftMood,
          tint: this.theme(),
          onChange: (mood: Mood | undefined) => { this.draftMood = mood; }
        })
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    } else {
      Row({ space: 16 }) {
        Row({ space: 4 }) {
          Text('👤').fontSize(13)
          Text(this.entry.authorRole).fontSize(15).fontColor(BubuColor.secondaryText)
        }
        if (this.entry.moodRaw) {
          Text(`${moodEmoji(this.entry.moodRaw as Mood)} ${this.entry.moodRaw}`)
            .fontSize(15).fontColor(BubuColor.secondaryText)
        }
        if (this.entry.locationName) {
          Row({ space: 4 }) {
            Text('📍').fontSize(13)
            Text(this.entry.locationName).fontSize(15).fontColor(BubuColor.secondaryText)
          }
        }
        Blank()
      }
      .width('100%')
    }
  }

  // MARK: 备注（对照 iOS noteSection：编辑态 TextArea，只读态文字）
  @Builder
  noteSection() {
    Column({ space: 8 }) {
      Text('此刻的记录')
        .fontSize(21).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      if (this.editing) {
        TextArea({ text: this.draftNote, placeholder: '此刻的布布……' })
          .fontSize(18).fontColor(BubuColor.warmBrown)
          .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
          .padding(16).width('100%').constraintSize({ minHeight: 100 })
          .onChange((v: string) => { this.draftNote = v; })
      } else if (this.entry.note && this.entry.note.length > 0) {
        Text(this.entry.note)
          .fontSize(18).fontColor(BubuColor.warmBrown).width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }

  // MARK: 语音记录（对照 iOS voiceNotesSection：列表 + 编辑态录制）
  @Builder
  voiceNotesSection() {
    if (this.voiceNotes.length > 0 || this.editing) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text('〰').fontSize(18)
          Text('语音记录').fontSize(21).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        }
        ForEach(this.voiceNotes, (voice: VoiceNote) => {
          if (voice.localFileName && voice.localFileName.length > 0) {
            Row({ space: 8 }) {
              VoicePlayerBubble({
                fileName: voice.localFileName,
                duration: voice.durationSeconds,
                waveform: voice.waveformSamples,
                tint: this.theme()
              })
                .layoutWeight(1)
              Text(voice.authorRole).fontSize(15).fontColor(BubuColor.secondaryText)
              if (this.editing) {
                Text('🗑').fontSize(20).fontColor(BubuColor.secondaryText)
                  .onClick(() => { this.deleteVoice(voice); })
              }
            }
            .width('100%').alignItems(VerticalAlign.Center)
          }
        }, (voice: VoiceNote) => voice.id)
        if (this.editing) {
          VoiceRecorderBar({
            tint: this.theme(),
            onFinished: (fileName: string, duration: number, waveform: number[]) => {
              this.addVoice(fileName, duration, waveform);
            }
          })
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  // MARK: AI 标签（对照 iOS tagsSection：媒体 aiTags 去重）
  @Builder
  tagsSection() {
    if (this.aiTags().length > 0) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text('🏷').fontSize(18)
          Text('自动识别').fontSize(21).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.aiTags(), (tag: string) => {
            Text(`# ${tag}`)
              .fontSize(15).fontColor(this.theme())
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#1AF28C9E').borderRadius(100)
              .margin({ right: 8, bottom: 8 })
          }, (tag: string) => tag)
        }
        .width('100%')
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  // MARK: 布布第一人称占位（对照 iOS firstPersonPlaceholder）
  @Builder
  firstPersonPlaceholder() {
    Row({ space: 10 }) {
      Text('✨').fontSize(18)
        .width(34).height(34).textAlign(TextAlign.Center)
        .backgroundColor('#1AF28C9E').borderRadius(17)
      Column({ space: 2 }) {
        Text('布布第一人称日记')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        Text(this.entry.firstPersonNote ?? '去 AI 工坊，把这一刻变成布布自己的话')
          .fontSize(13).fontColor(BubuColor.secondaryText)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(16).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#12F28C9E')
    .borderRadius(BubuRadius.small)
  }

  // MARK: 家人合奏（对照 iOS familyEnsembleSection：评论列表 + 添加）
  @Builder
  familyEnsembleSection() {
    Column({ space: 12 }) {
      Row() {
        Row({ space: 6 }) {
          Text('👪').fontSize(15)
          Text('家人合奏').fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        }
        Blank()
        Text('⊕').fontSize(26).fontColor(this.theme())
          .onClick(() => { this.showCommentSheet = true; })
      }
      .width('100%')

      if (this.realComments().length === 0) {
        Text('还没有人补充。点 + 号，说说你的视角。')
          .fontSize(15).fontColor(BubuColor.secondaryText)
      } else {
        ForEach(this.realComments(), (comment: Comment) => {
          this.commentRow(comment)
        }, (comment: Comment) => comment.id)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }

  @Builder
  commentRow(comment: Comment) {
    Column({ space: 6 }) {
      Text(comment.authorRole)
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.theme())
      if (comment.text && comment.text.length > 0) {
        Text(comment.text).fontSize(18).fontColor(BubuColor.warmBrown)
      }
      if (comment.voiceFileName && comment.voiceFileName.length > 0) {
        VoicePlayerBubble({
          fileName: comment.voiceFileName,
          duration: comment.voiceDuration,
          waveform: comment.voiceWaveform,
          tint: this.theme()
        })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ top: 6, bottom: 6 })
  }

  // 去重的 AI 标签（对照 iOS Array(Set(entry.media.flatMap { $0.aiTags }))）。
  private aiTags(): string[] {
    const set = new Set<string>();
    for (const m of this.media) {
      for (const t of m.aiTags) set.add(t);
    }
    return Array.from(set);
  }

  // MARK: 操作

  private async toggleEditing(): Promise<void> {
    if (this.editing) {
      // 完成：落库草稿（对照 iOS markEntryDirty + save）。
      const now = Date.now();
      const trimmed = this.draftNote.trim();
      await AppDatabase.shared.updateEntryFields(this.entry.id, {
        note: trimmed.length === 0 ? null : trimmed,
        moodRaw: this.draftMood ?? null,
        editedAt: now,
        syncState: SyncState.local
      });
      this.entry.note = trimmed.length === 0 ? undefined : trimmed;
      this.entry.moodRaw = this.draftMood;
      this.entry.editedAt = now;
      this.entry.syncState = SyncState.local;
    }
    animateTo({ duration: 200, curve: Curve.EaseInOut }, () => { this.editing = !this.editing; });
  }

  // 切换反应（对照 iOS toggleReaction）：同一人只保留一条；点已选的反应=取消。
  private async toggleReaction(r: Reaction): Promise<void> {
    const myRole = this.myRole();
    const already = this.reactionSummary().mine === r;
    // 删除我之前的反应评论。
    const mineReactions = this.comments.filter((c: Comment) => c.authorRole === myRole && ReactionUtil.isReaction(c));
    const store = AppDatabase.shared.raw;
    if (store) {
      for (const c of mineReactions) {
        const pred = new relationalStore.RdbPredicates('comment');
        pred.equalTo('id', c.id);
        await store.delete(pred);
      }
    }
    if (!already) {
      const now = Date.now();
      const comment: Comment = {
        id: util.generateRandomUUID(true),
        entryId: this.entry.id,
        authorRole: myRole,
        text: ReactionUtil.encodedText(r),
        voiceDuration: 0,
        voiceWaveform: [],
        syncState: SyncState.local,
        createdAt: now
      };
      await AppDatabase.shared.insertComment(comment);
      const event: FeedEvent = {
        id: util.generateRandomUUID(true),
        kind: FeedEventKind.commentAdded,
        actorRole: myRole,
        summary: `${myRole} ${ReactionUtil.label(r)}了这一刻 ${r}`,
        targetLocalId: this.entry.id,
        happenedAt: now,
        syncState: SyncState.synced,
        createdAt: now
      };
      await AppDatabase.shared.insertFeedEvent(event);
    }
    await this.load();
  }

  private async deleteMedia(m: Media): Promise<void> {
    MediaStore.shared.deleteLocalFiles(m.localFileName, m.thumbnailFileName);
    const store = AppDatabase.shared.raw;
    if (store) {
      const pred = new relationalStore.RdbPredicates('media');
      pred.equalTo('id', m.id);
      await store.delete(pred);
    }
    await AppDatabase.shared.updateEntryFields(this.entry.id, { editedAt: Date.now(), syncState: SyncState.local });
    await this.load();
  }

  private async deleteVoice(v: VoiceNote): Promise<void> {
    if (v.localFileName) MediaStore.shared.deleteLocalFiles(v.localFileName);
    const store = AppDatabase.shared.raw;
    if (store) {
      const pred = new relationalStore.RdbPredicates('voice_note');
      pred.equalTo('id', v.id);
      await store.delete(pred);
    }
    await AppDatabase.shared.updateEntryFields(this.entry.id, { editedAt: Date.now(), syncState: SyncState.local });
    await this.load();
  }

  private async addVoice(fileName: string, duration: number, waveform: number[]): Promise<void> {
    const now = Date.now();
    const voice: VoiceNote = {
      id: util.generateRandomUUID(true),
      entryId: this.entry.id,
      localFileName: fileName,
      durationSeconds: duration,
      authorRole: this.myRole(),
      waveformSamples: waveform,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertVoiceNote(voice);
    const event: FeedEvent = {
      id: util.generateRandomUUID(true),
      kind: FeedEventKind.voiceAdded,
      actorRole: this.myRole(),
      summary: '补充了一段语音记录',
      targetLocalId: this.entry.id,
      happenedAt: now,
      syncState: SyncState.synced,
      createdAt: now
    };
    await AppDatabase.shared.insertFeedEvent(event);
    await AppDatabase.shared.updateEntryFields(this.entry.id, { editedAt: now, syncState: SyncState.local });
    await this.load();
  }

  // 删除记录（对照 iOS deleteEntry：软删除 + entryArchived FeedEvent + dismiss）。
  private confirmDelete(): void {
    promptAction.showDialog({
      title: '删除这条记录？',
      message: '删除后会从时光轴隐藏，本地记录会标记为待同步删除。',
      buttons: [
        { text: '取消', color: BubuColor.secondaryText },
        { text: '删除', color: '#D9534F' }
      ]
    }).then(async (res) => {
      if (res.index === 1) {
        await AppDatabase.shared.archiveEntry(this.entry.id);
        const now = Date.now();
        const event: FeedEvent = {
          id: util.generateRandomUUID(true),
          kind: FeedEventKind.entryArchived,
          actorRole: this.myRole(),
          summary: '删除了一条时光轴记录',
          targetLocalId: this.entry.id,
          happenedAt: now,
          syncState: SyncState.synced,
          createdAt: now
        };
        await AppDatabase.shared.insertFeedEvent(event);
        promptAction.showToast({ message: '已删除' });
        if (this.onDismiss) this.onDismiss();
      }
    });
  }
}

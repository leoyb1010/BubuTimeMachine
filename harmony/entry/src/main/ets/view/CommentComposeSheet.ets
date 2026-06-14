import { Comment, FeedEvent } from '../models/Models';
import { SyncState, FeedEventKind } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { BubuColor, BubuRadius, BubuSpacing } from '../theme/BubuTheme';
import { VoicePlayerBubble, VoiceRecorderBar } from '../components/VoiceComponents';
import { util } from '@kit.ArkTS';

// MARK: - 家人合奏补充（对照 iOS Features/Timeline/CommentComposeSheet.swift）
// 以当前身份对某条记录补充文字 + 可选语音，多视角合成完整故事。
// iOS 用 .sheet + NavigationStack；ArkUI 由父级用 @State 控制显隐，这里是一块全屏面板，
// 顶部「取消 / 添加」对照 iOS toolbar 的取消 / 确认按钮。

interface VoiceDraft {
  fileName: string;
  duration: number;
  waveform: number[];
}

@Component
export struct CommentComposeSheet {
  // iOS: let entry: Entry —— 这里只需要它的 id 写评论 / FeedEvent。
  @Prop entryId: string;
  // 关闭面板（对照 iOS dismiss）。
  onClose?: () => void;
  // 保存成功后通知父级刷新评论列表。
  onSaved?: () => void;

  @State private text: string = '';
  @State private voice: VoiceDraft | null = null;

  private theme(): string { return BubuColor.primary; }
  private role(): string { return ServerConfig.shared.currentRole; }

  build() {
    Column() {
      // 顶栏：取消 / 标题 / 添加（对照 iOS navigationTitle「家人合奏」+ toolbar）。
      Row() {
        Button('取消')
          .backgroundColor(Color.Transparent)
          .fontColor(BubuColor.secondaryText)
          .fontSize(16)
          .onClick(() => { if (this.onClose) this.onClose(); })
        Blank()
        Text('家人合奏')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Button('添加')
          .backgroundColor(Color.Transparent)
          .fontColor(this.canSave() ? this.theme() : BubuColor.secondaryText)
          .fontSize(16).fontWeight(FontWeight.Bold)
          .enabled(this.canSave())
          .onClick(() => { this.save(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: BubuSpacing.section }) {
          // 身份提示行（对照 iOS HStack 角色 + 「从你的视角说说这一刻」）。
          Row({ space: 10 }) {
            Text(this.role())
              .fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.theme())
            Text('从你的视角说说这一刻')
              .fontSize(15).fontColor(BubuColor.secondaryText)
          }
          .width('100%')

          // 文字输入（对照 iOS TextField axis: .vertical, lineLimit 4...10）。
          TextArea({ text: this.text, placeholder: '这一刻，我记得……' })
            .fontSize(18)
            .fontColor(BubuColor.warmBrown)
            .backgroundColor(BubuColor.card)
            .borderRadius(BubuRadius.small)
            .padding(16)
            .width('100%')
            .constraintSize({ minHeight: 120 })
            .onChange((v: string) => { this.text = v; })

          // 语音：已录显示气泡 + 删除；未录显示录制条（对照 iOS if let v = voice ... else VoiceRecorderBar）。
          if (this.voice) {
            Row({ space: 8 }) {
              VoicePlayerBubble({
                fileName: this.voice!.fileName,
                duration: this.voice!.duration,
                waveform: this.voice!.waveform,
                tint: this.theme()
              })
                .layoutWeight(1)
              Text('🗑')
                .fontSize(26).fontColor(BubuColor.secondaryText)
                .onClick(() => { this.voice = null; })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          } else {
            VoiceRecorderBar({
              tint: this.theme(),
              onFinished: (fileName: string, duration: number, waveform: number[]) => {
                this.voice = { fileName: fileName, duration: duration, waveform: waveform };
              }
            })
          }
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(BubuColor.background)
  }

  private canSave(): boolean {
    return this.text.trim().length > 0 || this.voice !== null;
  }

  // 对照 iOS save()：写一条 Comment + 一条 commentAdded FeedEvent，并把 Entry 标脏。
  private async save(): Promise<void> {
    if (!this.canSave()) return;
    const now = Date.now();
    const trimmed = this.text.trim();
    const comment: Comment = {
      id: util.generateRandomUUID(true),
      entryId: this.entryId,
      authorRole: this.role(),
      text: trimmed.length === 0 ? undefined : trimmed,
      voiceFileName: this.voice ? this.voice.fileName : undefined,
      voiceDuration: this.voice ? this.voice.duration : 0,
      voiceWaveform: this.voice ? this.voice.waveform : [],
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertComment(comment);

    // Entry 标脏（对照 iOS entry.editedAt / syncState = .local）。
    await AppDatabase.shared.updateEntryFields(this.entryId, {
      editedAt: now, syncState: SyncState.local
    });

    const event: FeedEvent = {
      id: util.generateRandomUUID(true),
      kind: FeedEventKind.commentAdded,
      actorRole: this.role(),
      summary: trimmed.length === 0 ? '补充了一段语音' : `补充：${trimmed}`,
      targetLocalId: this.entryId,
      happenedAt: now,
      syncState: SyncState.synced,
      createdAt: now
    };
    await AppDatabase.shared.insertFeedEvent(event);

    if (this.onSaved) this.onSaved();
    if (this.onClose) this.onClose();
  }
}

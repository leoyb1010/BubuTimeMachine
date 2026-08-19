import { BubuColor, BubuFont, BubuShadow } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { BubuHaptics } from '../theme/BubuHaptics';
import { BubuIcon, BubuIconName } from '../components/BubuIcon';
import { AIService, nowISO } from '../services/AIService';
import { parseNaturalCaptureOfflineWire } from '../services/OnDeviceNaturalParser';
import { ServerConfig } from '../services/ServerConfig';
import {
  NaturalCaptureRequest, NaturalCaptureParseResult, decodeParseResult
} from '../services/NaturalCaptureDTO';
import { NaturalCaptureReviewSheet } from './NaturalCaptureReviewSheet';
import { AudioRecorder, RecorderState } from '../services/AudioRecorder';
import { MediaStore } from '../services/MediaStore';
import { common } from '@kit.AbilityKit';

// MARK: - 全局一句话记录入口（对照 iOS Features/NaturalCapture/NaturalCaptureBar.swift）
// 轻盈的「AI 记录卡」：写一句 → 解析 → 确认页 → 各模块落库。
// 不做聊天界面；失败温和降级，不暴露异常原文。
// 支持写一句或说一句；语音只走真实自托管 /transcribe，失败保留原音频供重试。
@Component
export struct NaturalCaptureBar {
  @State private text: string = '';
  @State private isParsing: boolean = false;
  @State private errorText: string | null = null;
  @State private slowHint: string | null = null;

  // 确认页路由（对照 sheet(item: reviewPayload)）。
  @State private reviewResult: NaturalCaptureParseResult | null = null;
  @State private reviewOriginalText: string = '';
  @State private pageIn: boolean = false;
  @State private isRecording: boolean = false;
  @State private isTranscribing: boolean = false;
  @State private recordingElapsed: number = 0;
  @State private pendingAudioFileName: string | undefined = undefined;
  private recordingTimer: number = -1;

  aboutToAppear(): void {
    this.getUIContext().animateTo(BubuMotion.gentle, () => { this.pageIn = true; });
  }

  aboutToDisappear(): void {
    this.stopRecordingTimer();
    if (AudioRecorder.shared.state === RecorderState.recording) AudioRecorder.shared.cancel();
  }

  private isBusy(): boolean {
    return this.isParsing || this.isTranscribing;
  }

  private trimmed(): string {
    return this.text.trim();
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          BubuIcon({ name: BubuIconName.sparkles, iconSize: 18, color: BubuColor.primary, strokeWidth: 1.8, filled: true })
            .width(34).height(34)
            .backgroundColor('#1AF28C9E')
            .borderRadius(17)

          if (this.isRecording) {
            Row({ space: 8 }) {
              Text('●').fontSize(12).fontColor(BubuColor.danger)
              Text(`布布在听… ${Math.floor(this.recordingElapsed)} 秒`)
                .fontSize(BubuFont.caption).fontColor(BubuColor.warmBrown)
              Blank()
              Text('取消').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
                .onClick(() => { this.cancelRecording(); })
            }.layoutWeight(1)
          } else if (this.isTranscribing) {
            Row({ space: 8 }) {
              LoadingProgress().width(22).height(22).color(BubuColor.primary)
              Text('正在听清布布说了什么…').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
              Blank()
            }.layoutWeight(1)
          } else if (this.isParsing) {
            Row({ space: 8 }) {
              LoadingProgress().width(22).height(22).color(BubuColor.primary)
              Text('正在识别这句话…')
                .fontSize(BubuFont.caption)
                .fontColor(BubuColor.secondaryText)
              Blank()
            }
            .layoutWeight(1)
          } else {
            TextInput({ text: this.text, placeholder: '写一句：布布今天……' })
              .fontSize(BubuFont.body)
              .layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.text = v; })
              .onSubmit(() => { this.parseText(); })

            // 发送按钮（对照 arrow.up.circle.fill）。
            BubuIcon({
              name: BubuIconName.send,
              iconSize: 25,
              color: this.trimmed().length === 0 ? '#80A98D82' : BubuColor.primary,
              strokeWidth: 2.4,
              filled: this.trimmed().length > 0
            })
              .width(34).height(34)
              .onClick(() => {
                if (this.trimmed().length === 0 || this.isBusy()) return;
                BubuHaptics.selection();
                this.parseText();
              })
          }

          Text(this.isRecording ? '⏹' : '🎙')
            .fontSize(this.isRecording ? 28 : 22)
            .fontColor(this.isRecording ? BubuColor.danger : BubuColor.primary)
            .opacity(this.isBusy() && !this.isRecording ? 0.45 : 1)
            .accessibilityText(this.isRecording ? '停止录音并识别' : '按一下开始说话')
            .onClick(() => {
              if (this.isParsing || this.isTranscribing) return;
              this.toggleRecording();
            })

        }
        .width('100%')
        .padding(12)
        .backgroundColor('#E8FFFFFF')
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(24)
        .border({ width: 1, color: '#8FFFFFFF' })
        .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })

        if (this.slowHint !== null && this.isParsing) {
          Text(this.slowHint)
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
            .padding({ left: 4, right: 4 })
        }

        if (this.errorText !== null) {
          Row({ space: 10 }) {
            Text(this.errorText).fontSize(11).fontColor(BubuColor.secondaryText).layoutWeight(1)
            if (this.pendingAudioFileName !== undefined && !this.isTranscribing) {
              Text('重试转写').fontSize(11).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
                .onClick(() => { this.transcribeAndParse(this.pendingAudioFileName!); })
            }
          }.width('100%').padding({ left: 4, right: 4 })
        }
      }
      .width('100%')
      .opacity(this.pageIn ? 1 : 0)
      .translate({ x: 0, y: this.pageIn ? 0 : BubuMotion.entranceOffsetY })
      .animation(BubuMotion.gentle)

      // 确认页（对照 sheet）。
      if (this.reviewResult !== null) {
        NaturalCaptureReviewSheet({
          result: this.reviewResult,
          originalText: this.reviewOriginalText,
          authorRole: ServerConfig.shared.currentRole,
          onSaved: () => { this.text = ''; },
          onDismiss: () => { this.reviewResult = null; }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  private async toggleRecording(): Promise<void> {
    const recorder = AudioRecorder.shared;
    if (recorder.state === RecorderState.recording) {
      const result = await recorder.stop();
      this.stopRecordingTimer();
      this.isRecording = false;
      if (result) await this.transcribeAndParse(result.fileName);
      return;
    }
    this.errorText = null;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!(await recorder.requestPermission(context))) {
      this.errorText = '需要麦克风权限，去系统设置里给布布开启吧。';
      return;
    }
    if (!(await recorder.start())) {
      this.errorText = '录音启动失败，稍后再试试。';
      return;
    }
    this.isRecording = true;
    this.recordingElapsed = 0;
    this.recordingTimer = setInterval(() => { this.recordingElapsed = recorder.elapsed; }, 100);
  }

  private async cancelRecording(): Promise<void> {
    await AudioRecorder.shared.cancel();
    this.isRecording = false;
    this.stopRecordingTimer();
  }

  private stopRecordingTimer(): void {
    if (this.recordingTimer >= 0) clearInterval(this.recordingTimer);
    this.recordingTimer = -1;
  }

  private async transcribeAndParse(fileName: string): Promise<void> {
    this.pendingAudioFileName = fileName;
    this.isTranscribing = true;
    this.errorText = null;
    try {
      const transcript = (await AIService.shared.transcribe(MediaStore.shared.fullPath(fileName))).trim();
      if (transcript.length === 0) {
        this.errorText = '没听清，可以再说一次或直接打字。';
        return;
      }
      this.text = transcript;
      MediaStore.shared.deleteMedia(fileName);
      this.pendingAudioFileName = undefined;
      await this.parseText();
    } catch (e) {
      this.errorText = '转写失败了，可以重试或直接打字。';
    } finally {
      this.isTranscribing = false;
    }
  }

  // MARK: 文字解析（对照 parseText）
  private async parseText(): Promise<void> {
    const input = this.trimmed();
    // 防重复提交：解析中 / 确认页已弹出时一律忽略。
    if (input.length === 0 || this.isParsing || this.reviewResult !== null) return;

    this.isParsing = true;
    this.errorText = null;
    this.slowHint = null;

    // 超过 8 秒还没结果：给一句安抚（对照 hintTask）。
    let slowTimer: number = setTimeout(() => {
      if (this.isParsing) this.slowHint = '布布还在仔细听这句话…再等几秒';
    }, 8000);

    try {
      const request: NaturalCaptureRequest = {
        text: input,
        childName: ServerConfig.shared.childName.length > 0 ? ServerConfig.shared.childName : '布布',
        timezone: 'Asia/Shanghai',
        referenceDate: nowISO()
      };
      let result: NaturalCaptureParseResult;
      try {
        result = await AIService.shared.parseNaturalCaptureFull(request);
      } catch (realError) {
        result = decodeParseResult(parseNaturalCaptureOfflineWire(request));
      }
      this.reviewOriginalText = input;
      this.reviewResult = result;
    } catch (e) {
      this.errorText = '智能识别暂时不可用，已保留原文，可以先用「记录此刻」保存。';
    } finally {
      clearTimeout(slowTimer);
      this.slowHint = null;
      this.isParsing = false;
    }
  }
}

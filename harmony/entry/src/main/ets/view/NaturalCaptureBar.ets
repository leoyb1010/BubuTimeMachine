import { promptAction } from '@kit.ArkUI';
import { BubuColor, BubuFont } from '../theme/BubuTheme';
import { AIService, nowISO } from '../services/AIService';
import { ServerConfig } from '../services/ServerConfig';
import {
  NaturalCaptureRequest, NaturalCaptureParseResult
} from '../services/NaturalCaptureDTO';
import { NaturalCaptureReviewSheet } from './NaturalCaptureReviewSheet';

// MARK: - 全局一句话记录入口（对照 iOS Features/NaturalCapture/NaturalCaptureBar.swift）
// 轻盈的「AI 记录卡」：写一句 → 解析 → 确认页 → 各模块落库。
// 不做聊天界面；失败温和降级，不暴露异常原文。
// NOTE: iOS 还支持「说一句」（AudioRecorder + transcribe）。本切片未携带 AudioRecorder 录音器契约，
// 故语音录制按钮保留为占位（点按提示），端点 AIService.transcribe 已就绪，待录音器接入后启用。
@Component
export struct NaturalCaptureBar {
  @State private text: string = '';
  @State private isParsing: boolean = false;
  @State private errorText: string | null = null;
  @State private slowHint: string | null = null;

  // 确认页路由（对照 sheet(item: reviewPayload)）。
  @State private reviewResult: NaturalCaptureParseResult | null = null;
  @State private reviewOriginalText: string = '';

  private isBusy(): boolean {
    return this.isParsing;
  }

  private trimmed(): string {
    return this.text.trim();
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Text('✨')
            .fontSize(17)
            .fontColor(BubuColor.primary)
            .width(34).height(34)
            .textAlign(TextAlign.Center)
            .backgroundColor('#1AF28C9E')
            .borderRadius(17)

          if (this.isParsing) {
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
            Text('⬆')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trimmed().length === 0 ? '#80A98D82' : BubuColor.primary)
              .width(34).height(34)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (this.trimmed().length === 0 || this.isBusy()) return;
                this.parseText();
              })
          }

          // 语音按钮（NOTE 占位）。
          Text('🎤')
            .fontSize(17)
            .fontColor(BubuColor.primary)
            .onClick(() => {
              promptAction.showToast({ message: '语音记录即将开放，先打字给布布吧 🌟' });
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(BubuColor.card)
        .borderRadius(22)

        if (this.slowHint !== null && this.isParsing) {
          Text(this.slowHint)
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
            .padding({ left: 4, right: 4 })
        }

        if (this.errorText !== null) {
          Text(this.errorText)
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
            .padding({ left: 4, right: 4 })
        }
      }
      .width('100%')

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
      const result: NaturalCaptureParseResult = await AIService.shared.parseNaturalCaptureFull(request);
      this.reviewOriginalText = input;
      this.reviewResult = result;
    } catch (e) {
      this.errorText = '智能识别暂时不可用，可以先用「记录此刻」保存。';
    } finally {
      clearTimeout(slowTimer);
      this.slowHint = null;
      this.isParsing = false;
    }
  }
}

import { CaptureModel, SelectedMediaPreview } from './CaptureModel';
import { CameraCaptureView } from './CameraCaptureView';
import { VideoCaptureView } from './VideoCaptureView';
import { Mood } from '../models/Enums';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { BubuHaptics } from '../theme/BubuHaptics';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';
import { BubuIcon, BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { MoodPicker } from '../components/MoodPicker';
import { VoiceRecorderBar, VoicePlayerBubble } from '../components/VoiceComponents';
import { MediaStore } from '../services/MediaStore';
import { AudioRecorder } from '../services/AudioRecorder';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

// MARK: - 快速记录面板（对照 iOS Features/Capture/QuickCaptureSheet.swift）
// 拍/选媒体 + 一句话 + 心情 + 语音。全程可选填，任一有内容即可存。
// iOS 用 .sheet 承载 NavigationStack；ArkUI 这里作为一个全屏 @Component，由父级以 bindSheet/条件渲染呈现。

@Component
export struct QuickCaptureSheet {
  @ObjectLink model: CaptureModel;
  // 保存成功后回调父级（刷新首页数据）。
  onSaved?: () => void;
  // 关闭面板回调（对照 iOS「以后再说」/ dismiss）。
  onClose?: () => void;
  // 打开「一句话智能记录」回调（对照 iOS showNaturalCapture）。
  onNaturalCapture?: () => void;

  private theme: string = BubuColor.primary;
  @State private pageIn: boolean = false;

  aboutToAppear(): void {
    animateTo(BubuMotion.gentle, () => { this.pageIn = true; });
  }

  build() {
    Stack() {
      Column() {
        // 顶部标题栏（对照 iOS navigationTitle「记录此刻」+ 取消/保存）。
        this.topBar()

        Scroll() {
          Column({ space: BubuSpacingItem }) {
            this.introCard()
            this.naturalCaptureEntry()
            this.primaryActions()
            this.cameraShortcuts()

            if (this.model.selectedPreviews.length > 0) {
              this.selectedPreviewGrid()
            }

            this.noteField()
            this.voiceCard()
            this.locationPrivacyCard()

            MoodPicker({
              selection: this.model.mood,
              tint: this.theme,
              onChange: (m: Mood | undefined) => { this.model.mood = m; }
            })

            if (this.model.lastSavedSummary !== null) {
              Row({ space: 6 }) {
                Text('✅').fontSize(14)
                Text(this.model.lastSavedSummary!)
                  .fontSize(BubuFont.caption)
                  .fontColor(BubuColor.success)
              }
              .width('100%')
            }

            Blank().height(12)
          }
          .padding(16)
          .width('100%')
          .opacity(this.pageIn ? 1 : 0)
          .translate({ x: 0, y: this.pageIn ? 0 : BubuMotion.entranceOffsetY })
          .animation(BubuMotion.gentle)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BubuColor.background)

      // 分析中遮罩（对照 iOS analyzingOverlay）。
      if (this.model.analyzingHint !== null) {
        Column({ space: 14 }) {
          LoadingProgress().width(48).height(48).color(this.theme)
          Text(this.model.analyzingHint!)
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.warmBrown)
        }
        .padding(28)
        .backgroundColor('#F2FFFFFF')
        .borderRadius(BubuRadius.card)
        .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }

  @Builder
  topBar() {
    Row() {
      Button('以后再说')
        .backgroundColor(Color.Transparent)
        .fontColor(BubuColor.secondaryText)
        .onClick(() => {
          this.model.showQuickCapture = false;
          this.onClose?.();
        })
      Blank()
      Text('记录此刻')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
      Button(this.model.isSaving ? '保存中…' : '保存')
        .fontWeight(FontWeight.Bold)
        .backgroundColor(this.model.canSave() && !this.model.isSaving ? BubuColor.primary : BubuColor.softFill)
        .fontColor(this.model.canSave() && !this.model.isSaving ? Color.White : BubuColor.secondaryText)
        .enabled(this.model.canSave() && !this.model.isSaving)
        .onClick(() => { this.doSave(); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  private async doSave(): Promise<void> {
    const ok = await this.model.save();
    if (ok) {
      BubuHaptics.success();
      promptAction.showToast({ message: '已经收好啦 🌟' });
      this.onSaved?.();
    } else if (this.model.saveError !== null) {
      promptAction.showToast({ message: this.model.saveError });
      this.model.saveError = null;
    }
  }

  @Builder
  introCard() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 54, expression: BubuExpression.happy })
      Column({ space: 4 }) {
        Text('这一刻想怎么留下？')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('可以拍一张、写一句，也可以把声音直接留给未来的布布。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#DBFFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(BubuRadius.card)
    .border({ width: 1, color: '#76FFFFFF' })
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  naturalCaptureEntry() {
    Row({ space: 12 }) {
      BubuIconBadge({
        name: BubuIconName.sparkles,
        badgeSize: 38,
        iconSize: 18,
        color: '#FFFFFF',
        fill: BubuColor.primary,
        radius: 19,
        strokeWidth: 1.8,
        filled: true
      })
      Column({ space: 3 }) {
        Text('一句话智能记录')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('身高、体重、餐睡、里程碑都能识别')
          .fontSize(12)
          .fontColor(BubuColor.secondaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(18).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(20)
    .border({ width: 1, color: '#99FFFFFF' })
    .shadow({ radius: 12, color: '#24000000', offsetY: 5 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      BubuHaptics.tapLight();
      this.onNaturalCapture?.();
    })
  }

  @Builder
  primaryActions() {
    Row({ space: 8 }) {
      this.actionCard('照片', BubuIconName.photo, '#61FFC2D6', () => { this.pickPhotos(); })
      this.actionCard('视频', BubuIconName.video, '#66DCC9FF', () => { this.pickVideos(); })
      this.actionCard('文字', BubuIconName.textBubble, '#66BFEBD2', () => {
        promptAction.showToast({ message: '在下方「写一句」里写下此刻' });
      })
      this.actionCard('语音', BubuIconName.waveform, '#66C4E4FF', () => {
        promptAction.showToast({ message: '在下方「说给布布」卡片里录音' });
      })
    }
    .width('100%')
  }

  @Builder
  cameraShortcuts() {
    Row({ space: 10 }) {
      this.cameraButton('拍照', BubuIconName.photo, '#FFF0F5', () => { this.requestCamera(false); })
      this.cameraButton('录像', BubuIconName.video, '#F2EEFF', () => { this.requestCamera(true); })
    }
    .width('100%')
  }

  @Builder
  cameraButton(title: string, iconName: string, fill: string, action: () => void) {
    Row({ space: 8 }) {
      BubuIconBadge({
        name: iconName,
        badgeSize: 28,
        iconSize: 15,
        color: BubuColor.deepRose,
        fill: fill,
        radius: 14,
        strokeWidth: 1.8
      })
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .layoutWeight(1)
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#CCFFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(18)
    .border({ width: 1, color: '#88FFFFFF' })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      BubuHaptics.selection();
      action();
    })
  }

  @Builder
  actionCard(title: string, iconName: string, tint: string, action: () => void) {
    Column({ space: 6 }) {
      BubuIconBadge({
        name: iconName,
        badgeSize: 36,
        iconSize: 18,
        color: BubuColor.deepRose,
        fill: tint,
        radius: 18,
        strokeWidth: 2.2
      })
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Bolder)
        .fontColor(BubuColor.warmBrown)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(78)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#EFFFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(20)
    .border({ width: 1, color: '#8FFFFFFF' })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      BubuHaptics.selection();
      action();
    })
  }

  @Builder
  photoPicker() {
    Row({ space: 14 }) {
      BubuIconBadge({
        name: BubuIconName.photo,
        badgeSize: 48,
        iconSize: 26,
        color: BubuColor.primary,
        fill: '#1AF28C9E',
        radius: 16,
        strokeWidth: 2.4
      })
      Column({ space: 4 }) {
        Text('从相册补充照片或视频')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('会自动认出拍摄时间、地点和画面内容')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(18).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => { this.pickPhotos(); })
  }

  @Builder
  selectedPreviewGrid() {
    Column({ space: 10 }) {
      Row() {
        Text(`已选 ${this.model.selectedPreviews.length} 个`)
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.secondaryText)
        Blank()
        if (this.model.isLoadingPreviews) {
          LoadingProgress().width(18).height(18).color(this.theme)
        }
      }
      .width('100%')

      Grid() {
        ForEach(this.model.selectedPreviews, (preview: SelectedMediaPreview) => {
          GridItem() {
            Stack() {
              if (preview.isVideo) {
                Column({ space: 8 }) {
                  BubuIconBadge({
                    name: BubuIconName.video,
                    badgeSize: 38,
                    iconSize: 19,
                    color: '#FFFFFF',
                    fill: BubuColor.primary,
                    radius: 19,
                    strokeWidth: 1.8,
                    filled: true
                  })
                  Text('视频')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(BubuColor.warmBrown)
                }
                .width('100%').height(104)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#F7EFFF')
                .borderRadius(BubuRadius.small)
              } else {
                Image(preview.uri)
                  .width('100%').height(104)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(BubuRadius.small)
              }
              Text('✕')
                .fontSize(16)
                .fontColor(Color.White)
                .width(24).height(24)
                .textAlign(TextAlign.Center)
                .backgroundColor('#73000000')
                .borderRadius(12)
                .margin(5)
                .onClick(() => { this.model.removePickedItem(preview.index); })
            }
            .alignContent(Alignment.TopEnd)
          }
        }, (preview: SelectedMediaPreview) => `${preview.index}-${preview.uri}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .height(Math.ceil(this.model.selectedPreviews.length / 3) * 112)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#B8FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(BubuRadius.card)
    .border({ width: 1, color: '#66FFFFFF' })
  }

  @Builder
  noteField() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        BubuMascotBadge({ badgeSize: 38, expression: BubuExpression.drawing })
        Column({ space: 2 }) {
          Text('写一句')
            .fontSize(BubuFont.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('不必完整，未来的布布会懂。')
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      TextArea({ placeholder: '此刻的布布……', text: $$this.model.note })
        .fontSize(BubuFont.body)
        .height(110)
        .backgroundColor('#A6FFF7F1')
        .borderRadius(BubuRadius.small)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#E8FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(BubuRadius.card)
    .border({ width: 1, color: '#76FFFFFF' })
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  voiceCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        BubuMascotBadge({ badgeSize: 38, expression: BubuExpression.love })
        Column({ space: 2 }) {
          Text('说给布布')
            .fontSize(BubuFont.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('点一下开始录，再点一下收好，会跟这条记录一起保存。')
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      this.voiceSection()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#E8FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(BubuRadius.card)
    .border({ width: 1, color: '#76FFFFFF' })
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  voiceSection() {
    if (this.model.pendingVoiceFileName !== null) {
      Row({ space: 8 }) {
        VoicePlayerBubble({
          fileName: this.model.pendingVoiceFileName!,
          duration: this.model.pendingVoiceDuration,
          waveform: this.model.pendingVoiceWaveform,
          tint: this.theme
        })
        Text('🗑')
          .fontSize(24)
          .onClick(() => { this.model.clearPendingVoice(); })
      }
      .width('100%')
    } else {
      VoiceRecorderBar({
        tint: this.theme,
        onFinished: (fileName: string, duration: number, waveform: number[]) => {
          this.model.setPendingVoice(fileName, duration, waveform);
        }
      })
    }
  }

  @Builder
  locationPrivacyCard() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 3 }) {
          Text('记录地点')
            .fontSize(BubuFont.caption)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('打开后会请求一次定位；有照片自带地点时优先使用照片地点。')
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.includeLocation })
          .selectedColor(this.theme)
          .onChange((on: boolean) => {
            this.model.includeLocation = on;
            if (!on) {
              this.model.currentLocationName = null;
              this.model.locationError = null;
            } else {
              // NOTE: 定位服务未接入本切片，仅置标志；真实定位由 LocationService 后续补。
              this.model.locationError = '定位将在记录时尝试获取';
            }
          })
      }
      .width('100%')

      if (this.model.currentLocationName !== null) {
        Text(`将记录：${this.model.currentLocationName!}`)
          .fontSize(11)
          .fontColor(this.theme)
      }
      if (this.model.locationError !== null) {
        Text(this.model.locationError!)
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#E8FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(BubuRadius.card)
    .border({ width: 1, color: '#76FFFFFF' })
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .alignItems(HorizontalAlign.Start)
  }

  // 系统相册选择照片（对照 iOS PhotosPicker）。
  private async pickPhotos(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 9;
      const res = await picker.select(opt);
      if (res.photoUris && res.photoUris.length > 0) {
        this.model.addPhotoUris(res.photoUris);
        promptAction.showToast({ message: `已选择 ${res.photoUris.length} 张照片` });
      }
    } catch (e) {
      promptAction.showToast({ message: '已取消' });
    }
  }

  private async pickVideos(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      opt.maxSelectNumber = 9;
      const res = await picker.select(opt);
      if (res.photoUris && res.photoUris.length > 0) {
        this.model.addVideoUris(res.photoUris);
        promptAction.showToast({ message: `已选择 ${res.photoUris.length} 段视频` });
      }
    } catch (e) {
      promptAction.showToast({ message: '已取消' });
    }
  }

  // 拍照 / 录像（对照 iOS requestCamera）。
  private async requestCamera(video: boolean): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.CAMERA']);
    } catch (e) {}
    if (video) {
      const uri = await VideoCaptureView.captureVideo(ctx);
      if (uri) {
        this.model.addVideoUri(uri);
      } else {
        promptAction.showToast({ message: '已取消或设备无相机，可从相册选择' });
      }
    } else {
      const uri = await CameraCaptureView.capturePhoto(ctx);
      if (uri) {
        this.model.addPhotoUri(uri);
      } else {
        promptAction.showToast({ message: '已取消或设备无相机，可从相册选择' });
      }
    }
  }
}

// 间距常量（对照 iOS BubuTheme.Spacing.item）。
const BubuSpacingItem: number = 16;

import { common } from '@kit.AbilityKit';
import { ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { CameraCaptureView } from './CameraCaptureView';
import { VoiceRecorderBar } from '../components/VoiceComponents';
import { MediaStore } from '../services/MediaStore';
import { EntryWriter } from '../services/EntryWriter';
import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';
import { SimpleTimelineView } from './SimpleTimelineView';

@Component
export struct SimpleModeView {
  onExit: () => void = () => {};
  @State profile: ChildProfile | null = null;
  @State showVoice: boolean = false;
  @State showTimeline: boolean = false;
  @State saving: boolean = false;
  @State notice: string = '';

  aboutToAppear(): void { this.reload(); }

  build() {
    if (this.showTimeline) {
      SimpleTimelineView({ onClose: () => { this.showTimeline = false; } })
    } else {
      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 6 }) {
            Text('👶').fontSize(64)
            Text('你好呀').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText)
            Text(this.profile?.name ?? ServerConfig.shared.childName)
              .fontSize(38).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
            if (this.profile) {
              Text(AgeCalculator.ageDescription(this.profile.birthday, Date.now()))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.deepRose)
            }
          }.width('100%')

          this.bigAction('📷', '拍一张', '给布布拍照片', BubuColor.primary, () => { this.capturePhoto(); })
          this.bigAction('🎙️', '说一段', '说句话给布布', BubuColor.info, () => { this.showVoice = !this.showVoice; })
          if (this.showVoice) {
            Column({ space: 10 }) {
              Text('点一下开始，说完再点一下').fontSize(18).fontColor(BubuColor.secondaryText)
              VoiceRecorderBar({
                tint: BubuColor.info,
                onFinished: (fileName: string, duration: number, waveform: number[]) => {
                  this.saveVoice(fileName, duration);
                }
              })
            }.width('100%').padding(18).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
          }
          this.bigAction('🖼️', '看布布', '翻翻最近的照片', BubuColor.success, () => { this.showTimeline = true; })

          if (this.saving) {
            Row({ space: 10 }) {
              LoadingProgress().width(28).height(28).color(BubuColor.primary)
              Text('正在收好…').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            }.padding(18)
          }
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.success)
              .width('100%').textAlign(TextAlign.Center).padding(16)
          }
          Button('切换到完整版').height(52).fontSize(17)
            .backgroundColor(BubuColor.card).fontColor(BubuColor.secondaryText)
            .onClick(() => { this.exit(); })
        }.width('100%').padding({ left: 22, right: 22, top: 24, bottom: 32 })
      }.width('100%').height('100%').backgroundColor(BubuColor.background)
    }
  }

  @Builder
  private bigAction(icon: string, title: string, subtitle: string, color: string, action: () => void) {
    Row({ space: 18 }) {
      Text(icon).fontSize(44).width(64).textAlign(TextAlign.Center)
      Column({ space: 5 }) {
        Text(title).fontSize(30).fontWeight(FontWeight.Bolder).fontColor(Color.White)
        Text(subtitle).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#EFFFFFFF')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(32).fontColor(Color.White)
    }.width('100%').height(118).padding({ left: 18, right: 18 })
    .backgroundColor(color).borderRadius(BubuRadius.card).enabled(!this.saving).onClick(action)
  }

  private async reload(): Promise<void> { this.profile = await AppDatabase.shared.fetchChildProfile(); }

  private async capturePhoto(): Promise<void> {
    if (this.saving) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const uri = await CameraCaptureView.capturePhoto(context);
    if (!uri) return;
    this.saving = true; this.notice = '';
    const fileName = MediaStore.shared.copyIntoStore(uri, uri.toLowerCase().endsWith('.png') ? 'png' : 'jpg');
    if (fileName) {
      await EntryWriter.entryWithPhoto('', fileName, ServerConfig.shared.currentRole);
      this.notice = '照片收好啦'; SyncEngine.shared.start();
    } else this.notice = '没有保存好，再试一次好吗';
    this.saving = false;
  }

  private async saveVoice(fileName: string, duration: number): Promise<void> {
    if (this.saving) return;
    this.saving = true; this.notice = ''; this.showVoice = false;
    try {
      await EntryWriter.entryWithPhoto('', null, ServerConfig.shared.currentRole, undefined, fileName, duration);
      this.notice = '话已经收好啦'; SyncEngine.shared.start();
    } catch (e) { this.notice = '没有保存好，再试一次好吗'; }
    this.saving = false;
  }

  private async exit(): Promise<void> {
    await ServerConfig.shared.exitSimpleMode();
    this.onExit();
  }
}

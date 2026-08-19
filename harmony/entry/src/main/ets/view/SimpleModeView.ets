import { common } from '@kit.AbilityKit';
import { ChildProfile, FamilyMember } from '../models/Models';
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
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { BubuHaptics } from '../theme/BubuHaptics';

@Component
export struct SimpleModeView {
  onExit: () => void = () => {};
  @State profile: ChildProfile | null = null;
  @State currentMember: FamilyMember | null = null;
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
          Column({ space: 8 }) {
            Row({ space: 7 }) {
              Text(this.currentMember?.avatarEmoji ?? this.roleEmoji()).fontSize(20)
              Text(`当前身份：${ServerConfig.shared.currentRole}`)
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText)
              Blank()
            }
            .width('100%')
            .accessibilityText(`当前身份：${ServerConfig.shared.currentRole}`)

            Row({ space: 14 }) {
              Stack() {
                if (this.childAvatarSrc().length > 0) {
                  Image(this.childAvatarSrc()).width(66).height(66).objectFit(ImageFit.Cover).borderRadius(33)
                } else {
                  Text('👶').fontSize(40)
                }
              }
              .width(66).height(66).backgroundColor(BubuColor.card).borderRadius(33)
              .border({ width: 2, color: BubuColor.peach })
              Column({ space: 2 }) {
                Text('记录的是').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText)
                Text(this.profile?.name ?? ServerConfig.shared.childName)
                  .fontSize(34).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
                if (this.profile) {
                  Text(AgeCalculator.ageDescription(this.profile.birthday, Date.now()))
                    .fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.deepRose)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }.width('100%')
          }.width('100%')

          this.bigAction(BubuIconName.photo, '拍一张', '给布布拍照片', BubuColor.primary, () => { this.capturePhoto(); })
          this.bigAction(BubuIconName.mic, '说一段', '说句话给布布', BubuColor.info, () => { this.showVoice = !this.showVoice; })
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
          this.bigAction(BubuIconName.clock, '看布布', '翻翻最近的照片', BubuColor.success, () => { this.showTimeline = true; })

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
  private bigAction(iconName: string, title: string, subtitle: string, color: string, action: () => void) {
    Row({ space: 18 }) {
      BubuIconBadge({ name: iconName, badgeSize: 64, iconSize: 34, color: '#FFFFFF',
        fill: '#24FFFFFF', radius: 22, strokeWidth: 2.8 })
      Column({ space: 5 }) {
        Text(title).fontSize(30).fontWeight(FontWeight.Bolder).fontColor(Color.White)
        Text(subtitle).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#EFFFFFFF')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(32).fontColor(Color.White)
    }.width('100%').constraintSize({ minHeight: 118 })
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(color).borderRadius(BubuRadius.card).enabled(!this.saving)
    .onClick(() => { BubuHaptics.tapLight(); action(); })
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const members = await AppDatabase.shared.fetchMembers();
    this.currentMember = members.find((member: FamilyMember): boolean =>
      member.relation === ServerConfig.shared.currentRole) ?? null;
  }

  private childAvatarSrc(): string {
    const name = this.profile?.avatarMediaFileName;
    return name && MediaStore.shared.exists(name) ? `file://${MediaStore.shared.fullPath(name)}` : '';
  }

  private roleEmoji(): string {
    switch (ServerConfig.shared.currentRole) {
      case '爸爸': return '👨';
      case '妈妈': return '👩';
      case '姥姥':
      case '奶奶': return '👵';
      case '姥爷':
      case '爷爷': return '👴';
      default: return '🙂';
    }
  }

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

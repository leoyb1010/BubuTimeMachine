import { ChildProfile, Entry } from '../models/Models';
import { Mood } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { EntryWriter } from '../services/EntryWriter';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor } from '../theme/BubuTheme';
import { IdentityCard } from './IdentityCard';
import { ChildProfileView } from './ChildProfileView';
import { HealthHomeView } from './HealthHomeView';
import { SettingsView } from './SettingsView';
import { AlbumView } from './AlbumView';
import { MediaStore } from '../services/MediaStore';
import { AudioRecorder } from '../services/AudioRecorder';
import { AIService } from '../services/AIService';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

// MARK: - 首页 · 成长仪表盘（对照 iOS CaptureHomeView）
// 身份卡 + 统计 + 大记录按钮。记录走 EntryWriter（与意图/小组件同一写入层）。
@Component
export struct HomeView {
  @State profile: ChildProfile | null = null;
  @State entries: Entry[] = [];
  @State noteDraft: string = '';
  @State showRecord: boolean = false;
  @State showProfile: boolean = false;
  @State showHealth: boolean = false;
  @State showSettings: boolean = false;
  @State showAlbum: boolean = false;
  @State pickedPhotoName: string | null = null;   // 已选并落盘的照片文件名
  @State photoCount: number = 0;
  @State recording: boolean = false;
  @State recordedVoice: string | null = null;
  @State recordedDur: number = 0;
  @State quickText: string = '';
  @State parsing: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.entries = await AppDatabase.shared.fetchEntries(false);
    this.photoCount = (await AppDatabase.shared.fetchAllPhotos()).length;
  }

  // 一句话记录：有 AI 则先解析规整，无 AI/失败则直接存原文（离线优先）
  private async quickCapture(): Promise<void> {
    const text = this.quickText.trim();
    if (text.length === 0) return;
    this.parsing = true;
    let note = text;
    let mood: Mood | undefined = undefined;
    try {
      if (AIService.shared.isConfigured) {
        const r = await AIService.shared.parseNaturalCapture(text);
        if (r.note && r.note.length > 0) note = r.note;
        if (r.mood) mood = r.mood as Mood;
      }
    } catch (e) {
      // 解析失败：用原文
    }
    try {
      await EntryWriter.quickTextEntry(note, ServerConfig.shared.currentRole, mood);
      this.quickText = '';
      await this.reload();
      promptAction.showToast({ message: '已经收好啦 🌟' });
    } catch (e) {
      promptAction.showToast({ message: '保存失败，稍后再试' });
    }
    this.parsing = false;
  }

  // 录音开始/停止
  private async toggleRecord(): Promise<void> {
    if (this.recording) {
      const res = await AudioRecorder.shared.stop();
      this.recording = false;
      if (res && res.fileName.length > 0) {
        this.recordedVoice = res.fileName;
        this.recordedDur = res.durationSec;
      }
    } else {
      // 申请麦克风权限
      try {
        const atManager = abilityAccessCtrl.createAtManager();
        await atManager.requestPermissionsFromUser(getContext(this), ['ohos.permission.MICROPHONE']);
      } catch (e) {}
      const ok = await AudioRecorder.shared.start();
      if (ok) {
        this.recording = true;
      } else {
        promptAction.showToast({ message: '无法开始录音，请检查麦克风权限' });
      }
    }
  }

  // 系统相册选一张照片 → 拷进沙盒，记下文件名
  private async pickPhoto(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 1;
      const res = await picker.select(opt);
      if (res.photoUris && res.photoUris.length > 0) {
        const uri = res.photoUris[0];
        const ext = uri.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        const name = MediaStore.shared.copyIntoStore(uri, ext);
        if (name) {
          this.pickedPhotoName = name;
        } else {
          promptAction.showToast({ message: '照片读取失败' });
        }
      }
    } catch (e) {
      promptAction.showToast({ message: '已取消' });
    }
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // 顶部：标题 + 设置入口
        Row() {
          Text('布布时光机').fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Text('⚙️').fontSize(22).onClick(() => { this.showSettings = true; })
        }.width('100%').padding({ top: 8 })

        if (this.profile) {
          // 卡片自身轻点翻面；右上「编辑」按钮进资料编辑
          IdentityCard({ profile: this.profile! })
          Text('编辑布布资料')
            .fontSize(12).fontColor(BubuColor.primary)
            .alignSelf(ItemAlign.End)
            .onClick(() => { this.showProfile = true; })
        } else {
          Column({ space: 10 }) {
            Text('布布时光机')
              .fontSize(28).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
            Button('建立布布的档案')
              .backgroundColor(BubuColor.primary)
              .onClick(() => { this.showProfile = true; })
          }.margin({ top: 24 })
        }

        // 大记录按钮
        Button() {
          Row() {
            Text('🍼').fontSize(40)
            Column() {
              Text('记录此刻').fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text('写一句、拍张照、说给布布听').fontSize(12).fontColor(BubuColor.secondaryText)
            }.alignItems(HorizontalAlign.Start).margin({ left: 12 })
            Blank()
          }.width('100%').padding(16)
        }
        .backgroundColor(BubuColor.card)
        .borderRadius(24)
        .width('100%')
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.95 })
        .onClick(() => { this.showRecord = true; })

        // 自然语言一句话记录（对照 iOS NaturalCaptureBar）
        Row({ space: 8 }) {
          TextInput({ text: $$this.quickText, placeholder: '一句话记录，如「布布今天会自己走路了」' })
            .layoutWeight(1).backgroundColor('#F3F3F3').borderRadius(12).height(44)
          Button(this.parsing ? '…' : '记')
            .width(48).backgroundColor(BubuColor.primary)
            .enabled(!this.parsing)
            .onClick(() => { this.quickCapture(); })
        }
        .width('100%').padding(8)
        .backgroundColor(BubuColor.card).borderRadius(16)

        // 统计行（照片卡可点进相册）
        Row({ space: 12 }) {
          this.statCard(`${this.entries.length}`, '个瞬间')
          Column({ space: 6 }) {
            Text(`${this.photoCount}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            Text('张照片').fontSize(12).fontColor(BubuColor.secondaryText)
          }
          .layoutWeight(1).padding({ top: 12, bottom: 12 })
          .backgroundColor(BubuColor.card).borderRadius(16)
          .onClick(() => { this.showAlbum = true; })
          if (this.profile) {
            this.statCard(`${AgeCalculator.daysUntilNextBirthday(this.profile!.birthday)}`, '天后生日')
          }
        }.width('100%')

        // 布布健康入口（对照 iOS healthEntryCard）
        Row({ space: 14 }) {
          Text('🩺').fontSize(34)
          Column() {
            Text('布布健康').fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            Text('餐食、零食、营养、睡眠、不舒服都记在这里').fontSize(12).fontColor(BubuColor.secondaryText).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(22).fontColor(BubuColor.secondaryText)
        }
        .width('100%').padding(16)
        .backgroundColor(BubuColor.card).borderRadius(20)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .onClick(() => { this.showHealth = true; })
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream)
    .width('100%').height('100%')
    .bindSheet($$this.showRecord, this.recordSheet(), { height: 320 })
    .bindSheet($$this.showProfile, this.profileSheet(), { height: '80%' })
    .bindSheet($$this.showHealth, this.healthSheet(), { height: '90%' })
    .bindSheet($$this.showSettings, this.settingsSheet(), { height: '90%' })
    .bindSheet($$this.showAlbum, this.albumSheet(), { height: '90%' })
  }

  @Builder
  profileSheet() {
    ChildProfileView()
  }

  @Builder
  healthSheet() {
    HealthHomeView()
  }

  @Builder
  settingsSheet() {
    SettingsView()
  }

  @Builder
  albumSheet() {
    AlbumView()
  }

  @Builder
  statCard(value: string, label: string) {
    Column({ space: 6 }) {
      Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(label).fontSize(12).fontColor(BubuColor.secondaryText)
    }
    .layoutWeight(1).padding({ top: 12, bottom: 12 })
    .backgroundColor(BubuColor.card).borderRadius(16)
  }

  @Builder
  recordSheet() {
    Column({ space: 14 }) {
      Text('记录布布此刻').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      TextArea({ placeholder: '写一句关于布布的瞬间…', text: $$this.noteDraft })
        .height(100).borderRadius(12).backgroundColor('#F3F3F3')

      // 加照片 + 录音
      Row({ space: 10 }) {
        Button(this.pickedPhotoName ? '✅ 已选照片' : '📷 加照片')
          .backgroundColor(this.pickedPhotoName ? BubuColor.success : '#F3F3F3')
          .fontColor(this.pickedPhotoName ? Color.White : BubuColor.warmBrown)
          .layoutWeight(1)
          .onClick(() => { this.pickPhoto(); })
        Button(this.recording ? '⏺ 停止录音' : (this.recordedVoice ? `✅ ${this.recordedDur}s` : '🎙 录一段'))
          .backgroundColor(this.recording ? BubuColor.primary : (this.recordedVoice ? BubuColor.success : '#F3F3F3'))
          .fontColor(this.recording || this.recordedVoice ? Color.White : BubuColor.warmBrown)
          .layoutWeight(1)
          .onClick(() => { this.toggleRecord(); })
      }.width('100%')

      Button('保存')
        .width('100%').backgroundColor(BubuColor.primary)
        .onClick(async () => {
          const text = this.noteDraft.trim();
          if (text.length === 0 && !this.pickedPhotoName && !this.recordedVoice) {
            promptAction.showToast({ message: '写一句话、加张照片，或录一段' });
            return;
          }
          try {
            await EntryWriter.entryWithPhoto(text, this.pickedPhotoName, ServerConfig.shared.currentRole,
              undefined, this.recordedVoice, this.recordedDur);
            this.noteDraft = '';
            this.pickedPhotoName = null;
            this.recordedVoice = null;
            this.recordedDur = 0;
            this.showRecord = false;
            await this.reload();
            promptAction.showToast({ message: '已经收好啦 🌟' });
          } catch (e) {
            promptAction.showToast({ message: '保存失败，稍后再试' });
          }
        })
    }
    .padding(20).width('100%')
  }
}

import { ChildProfile, Entry } from '../models/Models';
import { Mood, SyncState, moodEmoji } from '../models/Enums';
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
import { TimelineView } from './TimelineView';
import { EntryDetailView } from './EntryDetailView';
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
  @State showTimeline: boolean = false;
  @State showBirthday: boolean = false;
  @State selectedEntry: Entry | null = null;
  @State pickedPhotoName: string | null = null;   // 已选并落盘的照片文件名
  @State photoCount: number = 0;
  @State healthCount: number = 0;
  @State milestoneDoneCount: number = 0;
  @State pendingSyncCount: number = 0;
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
    this.entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    const photos = await AppDatabase.shared.fetchAllPhotos() ?? [];
    const health = await AppDatabase.shared.fetchHealth() ?? [];
    const milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    const capsules = await AppDatabase.shared.fetchCapsules() ?? [];
    this.photoCount = photos.length;
    this.healthCount = health.length;
    this.milestoneDoneCount = milestones.filter(m => m.happenedAt !== undefined).length;
    this.pendingSyncCount =
      this.entries.filter(e => e.syncState !== SyncState.synced).length +
      health.filter(h => h.syncState !== SyncState.synced).length +
      milestones.filter(m => m.syncState !== SyncState.synced).length +
      capsules.filter(c => c.syncState !== SyncState.synced).length;
  }

  private entryList(): Entry[] {
    return this.entries ?? [];
  }

  // 一句话记录：有 AI 则先解析规整，无 AI/失败则直接存原文（离线优先）
  private async quickCapture(): Promise<void> {
    const text = this.quickText.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '先写一句再记录' });
      return;
    }
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
    if (this.showRecord) {
      this.recordPanel()
    } else if (this.selectedEntry) {
      Column() {
        this.panelHeader('记录详情')
        EntryDetailView({
          entry: this.selectedEntry!,
          onDismiss: () => {
            this.selectedEntry = null;
            this.reload();
          }
        })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showProfile) {
      Column() {
        this.panelHeader('布布资料')
        ChildProfileView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showHealth) {
      Column() {
        this.panelHeader('布布健康')
        HealthHomeView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showSettings) {
      SettingsView({
        onClose: () => {
          this.showSettings = false;
          this.reload();
        }
      })
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showTimeline) {
      Column() {
        this.panelHeader('时光')
        TimelineView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showAlbum) {
      Column() {
        this.panelHeader('照片墙')
        AlbumView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showBirthday) {
      this.birthdayPanel()
    } else {
      this.homePage()
    }
  }

  @Builder
  homePage() {
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

        // 自然语言一句话记录（对照 iOS NaturalCaptureBar）
        Row({ space: 10 }) {
          Text('✨')
            .fontSize(18)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor('#FFF0F4')
            .borderRadius(18)
          TextInput({ text: $$this.quickText, placeholder: '写一句或说一句：布布今天……' })
            .layoutWeight(1)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .height(44)
          Button(this.parsing ? '…' : '↑')
            .width(44)
            .height(44)
            .backgroundColor(this.quickText.trim().length === 0 ? '#E3DDD8' : BubuColor.primary)
            .enabled(!this.parsing)
            .onClick(() => { this.quickCapture(); })
          Button(this.recording ? '■' : '🎙')
            .width(44)
            .height(44)
            .backgroundColor(this.recording ? BubuColor.primary : '#F3F3F3')
            .fontColor(this.recording ? Color.White : BubuColor.warmBrown)
            .onClick(() => { this.toggleRecord(); })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFFFFFF2')
        .borderRadius(22)
        .shadow({ radius: 10, color: '#1A000000', offsetY: 4 })

        // 大记录按钮（对照 iOS recordButton）
        Button() {
          Row() {
            Text('🍼').fontSize(46)
            Column() {
              Text('记录此刻').fontSize(24).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text('拍照、写一句、说给布布听').fontSize(13).fontColor(BubuColor.secondaryText)
            }.alignItems(HorizontalAlign.Start).margin({ left: 14 })
            Blank()
            Text('💗').fontSize(30).fontColor(BubuColor.primary)
          }.width('100%').padding(18)
        }
        .backgroundColor(BubuColor.card)
        .borderRadius(30)
        .width('100%')
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.95 })
        .onClick(() => { this.showRecord = true; })

        // 统计行：瞬间 / 照片 / 生日均可点
        Row({ space: 12 }) {
          this.statCard(`${this.entryList().length}`, '个瞬间', '✨', () => { this.showTimeline = true; })
          this.statCard(`${this.photoCount}`, '张照片', '🖼️', () => { this.showAlbum = true; })
          if (this.profile) {
            this.statCard(`${AgeCalculator.daysUntilNextBirthday(this.profile!.birthday)}`, '天后生日', '🎁', () => { this.showBirthday = true; })
          }
        }.width('100%')

        this.syncHealthStrip()
        this.onThisDaySection()

        // 布布健康入口（对照 iOS healthEntryCard）
        Row({ space: 14 }) {
          Text('🩺').fontSize(34)
          Column() {
            Text('布布健康').fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            Text('餐食、零食、营养补充、睡眠和不舒服都记在这里').fontSize(12).fontColor(BubuColor.secondaryText).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(22).fontColor(BubuColor.secondaryText)
        }
        .width('100%').padding(16)
        .backgroundColor(BubuColor.card).borderRadius(20)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .onClick(() => { this.showHealth = true; })

        this.dailyQuestionCard()
        this.recentStrip()
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream)
    .width('100%').height('100%')
  }

  @Builder
  panelHeader(title: string) {
    Row({ space: 12 }) {
      Button('返回')
        .backgroundColor('#F3F3F3')
        .fontColor(BubuColor.warmBrown)
        .onClick(() => {
          this.closePanel();
        })
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  private closePanel(): void {
    this.showRecord = false;
    this.showProfile = false;
    this.showHealth = false;
    this.showSettings = false;
    this.showAlbum = false;
    this.showTimeline = false;
    this.showBirthday = false;
    this.selectedEntry = null;
    this.reload();
  }

  @Builder
  statCard(value: string, label: string, icon: string, action: () => void) {
    Column({ space: 6 }) {
      Text(icon).fontSize(20).fontColor(BubuColor.primary)
      Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(label).fontSize(12).fontColor(BubuColor.secondaryText)
    }
    .layoutWeight(1).padding({ top: 12, bottom: 12 })
    .backgroundColor(BubuColor.card).borderRadius(16)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(action)
  }

  @Builder
  syncHealthStrip() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text(this.pendingSyncCount === 0 ? '☁️' : '🔄')
          .fontSize(22)
          .fontColor(this.pendingSyncCount === 0 ? BubuColor.success : BubuColor.primary)
        Column({ space: 2 }) {
          Text('本地已保存')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text(this.syncSummary())
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('查看')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFFCC')
    .borderRadius(14)
    .onClick(() => { this.showSettings = true; })
  }

  @Builder
  onThisDaySection() {
    if (this.onThisDayEntries().length > 0) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text('📅').fontSize(18)
          Text('那年今日')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('›').fontSize(16).fontColor(BubuColor.secondaryText)
          Blank()
        }
        .width('100%')

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.onThisDayEntries().slice(0, 8), (e: Entry) => {
              this.memoryCard(e)
            }, (e: Entry) => e.id)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(BubuColor.card)
      .borderRadius(20)
    }
  }

  @Builder
  memoryCard(e: Entry) {
    Column({ space: 6 }) {
      Text(moodEmoji(e.moodRaw as Mood | undefined))
        .fontSize(38)
        .width(96)
        .height(96)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFF0F4')
        .borderRadius(14)
      if (this.profile) {
        Text(AgeCalculator.compactAge(this.profile!.birthday, e.happenedAt))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
      }
      Text(this.yearsAgoText(e.happenedAt))
        .fontSize(10)
        .fontColor(BubuColor.secondaryText)
    }
    .width(108)
    .onClick(() => { this.selectedEntry = e; })
  }

  @Builder
  dailyQuestionCard() {
    Row({ space: 14 }) {
      Text('🤔').fontSize(38)
      Column({ space: 4 }) {
        Text('今日一问')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
        Text(this.todayQuestion())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('答一句')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor(BubuColor.primary)
        .borderRadius(16)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(20)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      this.quickText = `【今日一问】${this.todayQuestion()}\n`;
      promptAction.showToast({ message: '已放到上方记录框' });
    })
  }

  @Builder
  recentStrip() {
    if (this.entryList().length > 0) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text('🕐').fontSize(18)
          Text('最近的瞬间')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%')

        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.entryList().slice(0, 8), (e: Entry) => {
              this.recentCard(e)
            }, (e: Entry) => e.id)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
    }
  }

  @Builder
  recentCard(e: Entry) {
    Column({ space: 6 }) {
      Text(moodEmoji(e.moodRaw as Mood | undefined))
        .fontSize(32)
        .width(96)
        .height(72)
        .textAlign(TextAlign.Center)
        .backgroundColor(BubuColor.card)
        .borderRadius(16)
      Text(e.note && e.note.length > 0 ? e.note : '一条布布瞬间')
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(108)
    .onClick(() => { this.selectedEntry = e; })
  }

  @Builder
  birthdayPanel() {
    Column({ space: 16 }) {
      this.panelHeader('生日倒计时')
      Text('🎁')
        .fontSize(64)
      Text(this.profile ? `${AgeCalculator.daysUntilNextBirthday(this.profile!.birthday)} 天后生日` : '先建立布布档案')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      if (this.profile) {
        Text(`布布已经来到世界第 ${AgeCalculator.daysSinceBirth(this.profile!.birthday)} 天`)
          .fontSize(14)
          .fontColor(BubuColor.secondaryText)
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  private syncSummary(): string {
    if (!ServerConfig.shared.isConfigured) {
      return this.pendingSyncCount === 0 ? '离线也可用，暂无待同步' : `离线可用，${this.pendingSyncCount} 项等服务器`;
    }
    return this.pendingSyncCount === 0 ? '已和家里服务器同步' : `${this.pendingSyncCount} 项正在等待同步`;
  }

  private onThisDayEntries(): Entry[] {
    const now = new Date();
    return this.entryList().filter(e => {
      const d = new Date(e.happenedAt);
      return d.getMonth() === now.getMonth() &&
        d.getDate() === now.getDate() &&
        !this.isSameDay(e.happenedAt, Date.now());
    });
  }

  private isSameDay(a: number, b: number): boolean {
    const da = new Date(a);
    const db = new Date(b);
    return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
  }

  private yearsAgoText(ms: number): string {
    const years = new Date().getFullYear() - new Date(ms).getFullYear();
    return years <= 0 ? '今年' : `${years}年前的今天`;
  }

  private todayQuestion(): string {
    const infant: string[] = [
      '今天布布最像哪种小动物？',
      '她今天发出的最可爱的声音是什么？',
      '今天她盯着什么看了好久？',
      '今天她第一次尝了什么味道？'
    ];
    const toddler: string[] = [
      '她今天发明了什么新词？',
      '今天她最得意的一件事是什么？',
      '她今天说的哪句话把你逗乐了？',
      '今天她最舍不得放下的玩具是哪个？'
    ];
    const child: string[] = [
      '她今天问了什么让你答不上来的问题？',
      '今天她最骄傲的作品是什么？',
      '今天她说了什么暖心的话？',
      '她今天学会了什么新本领？'
    ];
    let bank = toddler;
    if (this.profile) {
      const now = new Date();
      const bd = new Date(this.profile!.birthday);
      const months = (now.getFullYear() - bd.getFullYear()) * 12 + (now.getMonth() - bd.getMonth());
      bank = months < 13 ? infant : (months < 37 ? toddler : child);
    }
    const daySeed = Math.floor(Date.now() / 86400000);
    return bank[Math.abs(daySeed) % bank.length];
  }

  @Builder
  recordPanel() {
    Column({ space: 14 }) {
      this.panelHeader('记录布布此刻')
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
    .padding(20).width('100%').height('100%').backgroundColor(BubuColor.cream)
  }
}

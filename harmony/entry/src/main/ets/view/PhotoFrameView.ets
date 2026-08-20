import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppDatabase } from '../data/AppDatabase';
import { Entry, Media } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';

interface PhotoFrameSlide {
  id: string;
  uri: string;
  caption: string;
  dateText: string;
  ageText: string;
  isOnThisDay: boolean;
}

@Component
export struct PhotoFrameView {
  onClose: () => void = () => {};
  @State private slides: PhotoFrameSlide[] = [];
  @State private index: number = 0;
  @State private paused: boolean = false;
  @State private showControls: boolean = true;
  @State private clockText: string = '';
  @State private zoomed: boolean = false;
  @State private dwell: number = 8;
  @StorageLink('bubuReduceMotion') private reduceMotion: boolean = false;
  private clockTimer: number = -1;
  private slideTimer: number = -1;

  aboutToAppear(): void {
    this.dwell = ServerConfig.shared.photoFrameDwellSeconds;
    this.load();
    this.updateClock();
    this.clockTimer = setInterval(() => { this.updateClock(); }, 1000);
    this.restartSlideTimer();
    this.keepScreenOn(true);
  }

  aboutToDisappear(): void {
    this.stopTimers();
    this.keepScreenOn(false);
  }

  private async load(): Promise<void> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false);
    const today = new Date();
    const priority: PhotoFrameSlide[] = [];
    const rest: PhotoFrameSlide[] = [];
    for (const entry of entries) {
      const media = await AppDatabase.shared.fetchMediaForEntry(entry.id);
      const photo = media.find((item: Media): boolean => item.typeRaw === 'photo');
      const uri = this.photoUri(photo);
      if (uri.length === 0 || !photo) continue;
      const happened = new Date(entry.happenedAt);
      const onThisDay = happened.getMonth() === today.getMonth() && happened.getDate() === today.getDate()
        && happened.getFullYear() < today.getFullYear();
      const slide: PhotoFrameSlide = {
        id: photo.id,
        uri,
        caption: (entry.note ?? entry.title ?? '布布的一天').substring(0, 40),
        dateText: BubuDateFormat.yearMonthDay(happened),
        ageText: profile ? AgeCalculator.ageDescription(profile.birthday, entry.happenedAt) : '',
        isOnThisDay: onThisDay
      };
      (onThisDay ? priority : rest).push(slide);
    }
    this.slides = priority.concat(PhotoFrameView.shuffled(rest));
    if (this.index >= this.slides.length) this.index = 0;
    this.animateCurrent();
  }

  private photoUri(photo: Media | undefined): string {
    if (!photo) return '';
    if (photo.localFileName && MediaStore.shared.exists(photo.localFileName)) {
      return `file://${MediaStore.shared.fullPath(photo.localFileName)}`;
    }
    if (photo.thumbnailFileName) return `file://${MediaStore.shared.thumbnailPath(photo.thumbnailFileName)}`;
    return '';
  }

  private current(): PhotoFrameSlide | undefined { return this.slides[this.index]; }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor(Color.Black)
      if (this.current()) {
        Image(this.current()!.uri).width('100%').height('100%').objectFit(ImageFit.Cover)
          .scale({ x: this.reduceMotion ? 1 : (this.zoomed ? 1.10 : 1.01),
            y: this.reduceMotion ? 1 : (this.zoomed ? 1.10 : 1.01) })
          .animation({ duration: this.reduceMotion ? 0 : this.dwell * 1000, curve: Curve.EaseInOut })
        Column().width('100%').height('100%').linearGradient({
          angle: 180, colors: [['#80000000', 0], ['#00000000', 0.35], ['#A6000000', 1]]
        })
        this.caption()
        if (this.showControls) this.controls()
      } else {
        Column({ space: 14 }) {
          Text('🖼️').fontSize(54)
          Text('还没有可播放的照片').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('先去记录几段带照片的时光，就能把这里变成布布的相框。')
            .fontSize(14).fontColor('#BFFFFFFF').textAlign(TextAlign.Center)
          Button('返回').onClick(() => { this.onClose(); })
        }.padding(40).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%')
    .onClick(() => { this.showControls = !this.showControls; })
  }

  @Builder
  private caption() {
    Column() {
      Row() {
        Blank()
        Column({ space: 2 }) {
          Text(this.clockText).fontSize(30).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text(`${ServerConfig.shared.childName}的相册`).fontSize(13).fontColor('#D9FFFFFF')
        }.alignItems(HorizontalAlign.End)
      }.width('100%')
      Blank()
      Column({ space: 6 }) {
        if (this.current()!.isOnThisDay) {
          Text('那年今日').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 }).backgroundColor('#D9ED9E3B').borderRadius(18)
        }
        Text(this.current()!.caption).fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White).maxLines(2)
        Text(`${this.current()!.dateText}${this.current()!.ageText ? ` · ${this.current()!.ageText}` : ''}`)
          .fontSize(14).fontColor('#E6FFFFFF')
      }.alignItems(HorizontalAlign.Start).width('100%')
    }.width('100%').height('100%').padding(28).hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private controls() {
    Column() {
      Row() {
        Button('关闭').onClick(() => { this.onClose(); })
        Blank()
        Text(`${this.index + 1} / ${this.slides.length}`).fontSize(14).fontColor(Color.White)
      }.width('100%')
      Blank()
      Row({ space: 20 }) {
        Button('上一张').onClick(() => { this.advance(-1); })
        Button(this.paused ? '继续' : '暂停').onClick(() => { this.paused = !this.paused; this.restartSlideTimer(); })
        Button('下一张').onClick(() => { this.advance(1); })
        Button(`${this.dwell} 秒`).onClick(() => { this.cycleDwell(); })
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height('100%').padding(28)
  }

  private advance(delta: number): void {
    if (this.slides.length === 0) return;
    this.index = (this.index + delta + this.slides.length) % this.slides.length;
    this.animateCurrent();
    this.restartSlideTimer();
  }

  private animateCurrent(): void {
    if (this.reduceMotion) { this.zoomed = false; return; }
    this.zoomed = false;
    setTimeout(() => { this.zoomed = true; }, 30);
  }

  private cycleDwell(): void {
    const values = [5, 8, 15, 30];
    const index = values.indexOf(this.dwell);
    this.dwell = values[(index + 1) % values.length];
    ServerConfig.shared.setPhotoFrameDwellSeconds(this.dwell);
    this.restartSlideTimer();
  }

  private restartSlideTimer(): void {
    if (this.slideTimer >= 0) clearInterval(this.slideTimer);
    this.slideTimer = -1;
    if (!this.paused) this.slideTimer = setInterval(() => { this.advance(1); }, this.dwell * 1000);
  }

  private stopTimers(): void {
    if (this.clockTimer >= 0) clearInterval(this.clockTimer);
    if (this.slideTimer >= 0) clearInterval(this.slideTimer);
    this.clockTimer = -1;
    this.slideTimer = -1;
  }

  private updateClock(): void { this.clockText = BubuDateFormat.shortTime(new Date()); }

  private async keepScreenOn(enabled: boolean): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const appWindow = await window.getLastWindow(context);
      await appWindow.setWindowKeepScreenOn(enabled);
    } catch (e) {}
  }

  private static shuffled(values: PhotoFrameSlide[]): PhotoFrameSlide[] {
    const result = values.slice();
    for (let index = result.length - 1; index > 0; index--) {
      const target = Math.floor(Math.random() * (index + 1));
      const value = result[index];
      result[index] = result[target];
      result[target] = value;
    }
    return result;
  }
}

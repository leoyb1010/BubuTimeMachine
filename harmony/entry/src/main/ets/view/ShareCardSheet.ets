import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppDatabase } from '../data/AppDatabase';
import { ChildProfile, Entry, Media } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuHaptics } from '../theme/BubuHaptics';
import { MediaStore } from '../services/MediaStore';
import { ShareService } from '../services/ShareService';
import { ShareCardExporter, ShareCardInput, ShareCardLayout } from '../services/media/ShareCardExporter';

@Component
export struct ShareCardSheet {
  @Prop entry: Entry;
  onClose?: () => void;

  @State private profile: ChildProfile | null = null;
  @State private layout: ShareCardLayout = ShareCardLayout.portrait;
  @State private showAge: boolean = true;
  @State private previewPath: string = '';
  @State private currentPhotoPath: string = '';
  @State private thenPhotoPath: string = '';
  @State private thenEntry: Entry | null = null;
  @State private rendering: boolean = false;
  @State private errorText: string = '';
  private generatedPaths: Set<string> = new Set<string>();

  aboutToAppear(): void { this.prepare(); }
  aboutToDisappear(): void { this.cleanup(); }

  private async prepare(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const allEntries = await AppDatabase.shared.fetchEntries(false);
    const allMedia = await AppDatabase.shared.fetchAllMedia();
    this.currentPhotoPath = this.firstVisualPath(allMedia.filter((item: Media): boolean => item.entryId === this.entry.id));

    const date = new Date(this.entry.happenedAt);
    const candidate = allEntries.find((item: Entry): boolean => {
      if (item.id === this.entry.id || item.happenedAt >= this.entry.happenedAt) return false;
      const oldDate = new Date(item.happenedAt);
      if (oldDate.getMonth() !== date.getMonth() || oldDate.getDate() !== date.getDate()) return false;
      return this.firstVisualPath(allMedia.filter((media: Media): boolean => media.entryId === item.id)).length > 0;
    });
    if (candidate) {
      this.thenEntry = candidate;
      this.thenPhotoPath = this.firstVisualPath(allMedia.filter((item: Media): boolean => item.entryId === candidate.id));
    }
    await this.renderPreview();
  }

  private firstVisualPath(media: Media[]): string {
    const ordered = media.slice().sort((a: Media, b: Media): number => a.createdAt - b.createdAt);
    for (const item of ordered.filter((value: Media): boolean => value.typeRaw === 'photo')) {
      const path = this.existingMediaPath(item);
      if (path.length > 0) return path;
    }
    for (const item of ordered.filter((value: Media): boolean => value.typeRaw === 'video')) {
      if (item.thumbnailFileName) {
        const path = MediaStore.shared.thumbnailPath(item.thumbnailFileName);
        if (ShareCardSheet.exists(path)) return path;
      }
    }
    return '';
  }

  private existingMediaPath(media: Media): string {
    if (media.localFileName) {
      const original = MediaStore.shared.fullPath(media.localFileName);
      if (ShareCardSheet.exists(original)) return original;
    }
    if (media.thumbnailFileName) {
      const thumbnail = MediaStore.shared.thumbnailPath(media.thumbnailFileName);
      if (ShareCardSheet.exists(thumbnail)) return thumbnail;
    }
    return '';
  }

  private makeInput(): ShareCardInput {
    const age = this.showAge && this.profile
      ? AgeCalculator.compactAge(this.profile!.birthday, this.entry.happenedAt) : undefined;
    const thenAge = this.showAge && this.profile && this.thenEntry
      ? AgeCalculator.compactAge(this.profile!.birthday, this.thenEntry!.happenedAt) : undefined;
    return {
      entryId: this.entry.id,
      childName: this.profile?.name ?? '布布',
      dateText: BubuDateFormat.monthDay(new Date(this.entry.happenedAt)),
      ageText: age,
      note: ShareCardSheet.firstNonEmpty(this.entry.firstPersonNote, this.entry.note, this.entry.title),
      photoPath: this.currentPhotoPath.length > 0 ? this.currentPhotoPath : undefined,
      thenPhotoPath: this.thenPhotoPath.length > 0 ? this.thenPhotoPath : undefined,
      thenDateText: this.thenEntry ? BubuDateFormat.monthDay(new Date(this.thenEntry!.happenedAt)) : undefined,
      thenAgeText: thenAge,
      eraText: ShareCardSheet.eraLabel(this.entry.happenedAt),
      thenEraText: this.thenEntry ? ShareCardSheet.eraLabel(this.thenEntry!.happenedAt) : '那年'
    };
  }

  private async renderPreview(): Promise<void> {
    if (this.rendering) return;
    this.rendering = true;
    this.errorText = '';
    try {
      const path = await ShareCardExporter.shared.renderToFile(this.makeInput(), this.layout);
      this.previewPath = path;
      this.generatedPaths.add(path);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '分享卡生成失败';
    }
    this.rendering = false;
  }

  private async share(): Promise<void> {
    if (this.previewPath.length === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShareService.shareImage(context, this.previewPath, `${this.profile?.name ?? '布布'}的成长时光`);
    BubuHaptics.success();
  }

  build() {
    Column() {
      Row() {
        Button('取消').backgroundColor('#00000000').fontColor(BubuColor.secondaryText)
          .onClick(() => { if (this.onClose) this.onClose(); })
        Blank()
        Text('分享这一刻').fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text('      ')
      }
      .width('100%').padding({ left: 12, right: 12, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          Stack() {
            if (this.previewPath.length > 0) {
              Image(`file://${this.previewPath}`).width('100%').constraintSize({ maxHeight: 430 })
                .objectFit(ImageFit.Contain).borderRadius(BubuRadius.card)
                .accessibilityText(`${this.layout === ShareCardLayout.thenNow ? '那年今日' : '成长'}分享卡预览`)
            } else {
              LoadingProgress().width(44).height(44).color(BubuColor.primary)
            }
          }
          .width('100%').height(430).backgroundColor(BubuColor.softFill).borderRadius(BubuRadius.card)

          Row({ space: 8 }) {
            this.layoutButton('竖版', ShareCardLayout.portrait)
            this.layoutButton('方版', ShareCardLayout.square)
            if (this.currentPhotoPath.length > 0 && this.thenPhotoPath.length > 0) {
              this.layoutButton('那年今日', ShareCardLayout.thenNow)
            }
          }.width('100%')

          Row() {
            Column({ space: 3 }) {
              Text('显示当时年龄').fontSize(BubuFont.body).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
              Text('只显示“2岁2个月”，不会出现出生日期').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showAge })
              .selectedColor(BubuColor.primary)
              .onChange((value: boolean) => { this.showAge = value; this.renderPreview(); })
          }
          .width('100%').padding(14).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)

          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(BubuFont.caption).fontColor(BubuColor.danger).width('100%')
          }

          Button(this.rendering ? '正在生成…' : '分享图片')
            .width('100%').height(54).borderRadius(27)
            .backgroundColor(BubuColor.primary).fontColor(Color.White).fontWeight(FontWeight.Bold)
            .enabled(!this.rendering && this.previewPath.length > 0)
            .onClick(() => { this.share(); })
          Blank().height(24)
        }
        .width('100%').padding(16)
      }.layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  private layoutButton(title: string, value: ShareCardLayout) {
    Text(title).fontSize(BubuFont.body).fontWeight(FontWeight.Medium)
      .fontColor(this.layout === value ? Color.White : BubuColor.warmBrown)
      .textAlign(TextAlign.Center).layoutWeight(1).height(42)
      .backgroundColor(this.layout === value ? BubuColor.primary : BubuColor.softFill).borderRadius(21)
      .onClick(() => { this.layout = value; BubuHaptics.selection(); this.renderPreview(); })
  }

  private cleanup(): void {
    for (const path of this.generatedPaths) {
      try { if (fileIo.accessSync(path)) fileIo.unlinkSync(path); } catch (e) {}
    }
    this.generatedPaths.clear();
  }

  private static exists(path: string): boolean {
    try { return fileIo.accessSync(path); } catch (e) { return false; }
  }

  private static firstNonEmpty(...values: Array<string | undefined>): string | undefined {
    for (const value of values) {
      if (value && value.trim().length > 0) return value.trim();
    }
    return undefined;
  }

  private static eraLabel(epochMs: number): string {
    const year = new Date(epochMs).getFullYear();
    return year === new Date().getFullYear() ? '今年' : `${year}年`;
  }
}

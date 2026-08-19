import { PhotoEventGroup } from '../models/PhotoIntake';
import { PhotoIntakeService } from '../services/PhotoIntakeService';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';

@Component
export struct PhotoInboxView {
  onClose: () => void = () => {};

  @State groups: PhotoEventGroup[] = [];
  @State scanning: boolean = false;
  @State processingGroupId: string = '';
  @State notice: string = '';
  @State errorText: string = '';
  @State identityEnabled: boolean = false;

  aboutToAppear(): void {
    this.identityEnabled = PhotoIntakeService.shared.identityEnabled();
    this.reload();
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .backgroundColor(BubuColor.softFill)
          .fontColor(BubuColor.warmBrown)
          .onClick(this.onClose)
        Text('照片收件箱')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text('把最近照片按一次出游、一次聚会自动分组')
              .fontSize(BubuFont.body)
              .fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown)
            Text('只保存候选状态；你点“收好”后才复制原片并进入时光轴。')
              .fontSize(13)
              .fontColor(BubuColor.secondaryText)
              .textAlign(TextAlign.Center)
          }
          .width('100%').padding(18)
          .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)

          Button(this.scanning ? '正在扫描…' : '扫描最近 14 天')
            .width('100%').height(52)
            .enabled(!this.scanning && this.processingGroupId.length === 0)
            .backgroundColor(this.scanning ? BubuColor.softFill : BubuColor.primary)
            .fontColor(this.scanning ? BubuColor.secondaryText : Color.White)
            .borderRadius(BubuRadius.button)
            .onClick(() => { this.scan(); })

          Row() {
            Column({ space: 3 }) {
              Text('用头像认布布').fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text('只在本机比较，不上传人脸；只做提示，不自动隐藏照片。')
                .fontSize(12).fontColor(BubuColor.secondaryText)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.identityEnabled })
              .selectedColor(BubuColor.primary)
              .onChange((enabled: boolean) => {
                this.identityEnabled = enabled;
                PhotoIntakeService.shared.setIdentityEnabled(enabled);
              })
          }.width('100%').padding(14).backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)

          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(13).fontColor(BubuColor.success)
              .width('100%').padding(12)
              .backgroundColor('#168CB894').borderRadius(BubuRadius.small)
          }
          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(13).fontColor(BubuColor.danger)
              .width('100%').padding(12)
              .backgroundColor('#14DB3B47').borderRadius(BubuRadius.small)
          }

          if (!this.scanning && this.groups.length === 0) {
            Column({ space: 8 }) {
              Text('✓').fontSize(36).fontColor(BubuColor.success)
              Text('暂时没有待整理的照片')
                .fontSize(BubuFont.body).fontColor(BubuColor.warmBrown)
              Text('以后再来扫描，已经收好或忽略的照片不会重复出现。')
                .fontSize(13).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
            }
            .width('100%').padding(24)
            .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
          }

          ForEach(this.groups, (group: PhotoEventGroup) => {
            this.groupCard(group)
          }, (group: PhotoEventGroup): string => group.id)
        }
        .width('100%').padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  private groupCard(group: PhotoEventGroup) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        ForEach(group.assetUris.slice(0, 3), (uri: string) => {
          Image(uri)
            .layoutWeight(1).height(108)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        }, (uri: string): string => uri)
      }
      .width('100%')

      Row() {
        Column({ space: 3 }) {
          Text(this.groupDate(group))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Text(this.groupSummary(group))
            .fontSize(12).fontColor(BubuColor.secondaryText)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (group.assetUris.length > 3) {
          Text(`+${group.assetUris.length - 3}`)
            .fontSize(13).fontColor(BubuColor.primary)
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('忽略这组')
          .layoutWeight(1).height(48)
          .enabled(this.processingGroupId.length === 0)
          .backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
          .borderRadius(BubuRadius.button)
          .onClick(() => { this.ignore(group); })
        Button(this.processingGroupId === group.id ? '正在收好…' : '收进时光机')
          .layoutWeight(1).height(48)
          .enabled(this.processingGroupId.length === 0)
          .backgroundColor(BubuColor.primary).fontColor(Color.White)
          .borderRadius(BubuRadius.button)
          .onClick(() => { this.accept(group); })
      }
      .width('100%')
    }
    .width('100%').padding(14)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  private async reload(): Promise<void> {
    this.groups = await PhotoIntakeService.shared.cachedGroups();
  }

  private async scan(): Promise<void> {
    if (this.scanning) return;
    this.scanning = true;
    this.notice = '';
    this.errorText = '';
    try {
      this.groups = await PhotoIntakeService.shared.scanRecent();
      this.notice = this.groups.length === 0 ? '最近照片都整理好了' : `发现 ${this.groups.length} 组待整理照片`;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '扫描照片失败，请稍后重试';
    } finally {
      this.scanning = false;
    }
  }

  private async accept(group: PhotoEventGroup): Promise<void> {
    if (this.processingGroupId.length > 0) return;
    this.processingGroupId = group.id;
    this.notice = '';
    this.errorText = '';
    try {
      const result = await PhotoIntakeService.shared.accept(group);
      this.notice = result.failedCount === 0
        ? `已收好 ${result.acceptedCount} 个瞬间`
        : `已收好 ${result.acceptedCount} 个，另有 ${result.failedCount} 个稍后重试`;
      await this.reload();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '保存失败，请稍后重试';
    } finally {
      this.processingGroupId = '';
    }
  }

  private async ignore(group: PhotoEventGroup): Promise<void> {
    if (this.processingGroupId.length > 0) return;
    this.processingGroupId = group.id;
    await PhotoIntakeService.shared.ignore(group);
    this.notice = '这组照片以后不会再提醒';
    this.processingGroupId = '';
    await this.reload();
  }

  private groupDate(group: PhotoEventGroup): string {
    const date = new Date(group.startedAt);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:${`${date.getMinutes()}`.padStart(2, '0')}`;
  }

  private groupSummary(group: PhotoEventGroup): string {
    const parts: string[] = [];
    if (group.photoCount > 0) parts.push(`${group.photoCount} 张照片`);
    if (group.videoCount > 0) parts.push(`${group.videoCount} 段视频`);
    if (group.movingPhotoCount > 0) parts.push(`${group.movingPhotoCount} 张动态照片`);
    if (group.likelyChildCount > 0) parts.push(`可能有布布 ${group.likelyChildCount} 张`);
    return parts.join(' · ');
  }
}

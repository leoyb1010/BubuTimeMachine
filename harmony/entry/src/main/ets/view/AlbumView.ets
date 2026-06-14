import { Entry, Media, ChildProfile } from '../models/Models';
import { MediaType } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuRadius, BubuFont, BubuShadow } from '../theme/BubuTheme';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { AlbumDetailView } from './AlbumDetailView';
import { AlbumMediaItem, SystemAlbum, SystemAlbumFactory, albumCover, albumCount } from './SystemAlbum';

// MARK: - 布布的相册（对照 iOS Features/Album/AlbumHomeView.swift）
// 首页「张照片」入口的落地页：自动整理的系统相册（全部/最近/小视频/有地点/按月份/按月龄）。
@Component
export struct AlbumView {
  // 相册分组缓存：媒体没变就不重算（对照 @State featured/monthly/byAge）。
  @State private featured: SystemAlbum[] = [];
  @State private monthly: SystemAlbum[] = [];
  @State private byAge: SystemAlbum[] = [];
  @State private totalCount: number = 0;
  @State private built: boolean = false;
  @State private birthdayMs: number | undefined = undefined;

  // 内部导航：选中相册 → 相册详情（对照 NavigationLink → AlbumDetailView）。
  @State private detailAlbum: SystemAlbum | null = null;

  aboutToAppear(): void {
    this.rebuildAlbums();
  }

  // 对照 rebuildAlbums()：把所有记录里的照片/视频汇成 AlbumMediaItem 再分组。
  private async rebuildAlbums(): Promise<void> {
    const entries: Entry[] = await AppDatabase.shared.fetchEntries(false);
    const profile: ChildProfile | null = await AppDatabase.shared.fetchChildProfile();
    this.birthdayMs = profile !== null ? profile.birthday : undefined;

    const items: AlbumMediaItem[] = [];
    for (const entry of entries) {
      const media: Media[] = await AppDatabase.shared.fetchMediaForEntry(entry.id);
      const valid = media
        .filter((m: Media) => m.typeRaw === MediaType.photo || m.typeRaw === MediaType.video)
        .sort((a: Media, b: Media) => a.createdAt - b.createdAt);
      for (const m of valid) {
        items.push({ id: m.id, media: m, entry: entry });
      }
    }

    this.totalCount = items.length;
    this.featured = SystemAlbumFactory.featured(items);
    this.monthly = SystemAlbumFactory.monthly(items);
    this.byAge = SystemAlbumFactory.byAgeMonth(items, this.birthdayMs);
    this.built = true;
  }

  // 相册图标 SF Symbol → emoji（对照 iOS Image(systemName: album.icon)）。
  private iconEmoji(icon: string): string {
    switch (icon) {
      case 'photo.stack': return '🖼️';
      case 'clock': return '🕐';
      case 'video': return '🎬';
      case 'mappin.and.ellipse': return '📍';
      case 'calendar': return '📅';
      case 'birthday.cake': return '🎂';
      default: return '📷';
    }
  }

  build() {
    Stack() {
      // 列表页
      Scroll() {
        Column({ space: 18 }) {
          this.headerCard()

          if (this.built && this.totalCount === 0) {
            this.emptyState()
          } else {
            this.featuredRow()

            if (this.monthly.length > 0) {
              this.albumSection('按月份', this.monthly)
            }
            if (this.byAge.length > 0) {
              this.albumSection('按月龄', this.byAge)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BubuColor.background)
      .align(Alignment.Top)

      // 相册详情（对照 NavigationLink push）。
      if (this.detailAlbum !== null) {
        AlbumDetailView({
          title: this.detailAlbum.title,
          items: this.detailAlbum.items,
          onBack: () => { this.detailAlbum = null; }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 对照 headerCard
  @Builder
  headerCard() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 52, expression: BubuExpression.happy })
      Column({ space: 4 }) {
        Text('布布的相册')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('自动整理每一张长大的证据')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  // 对照 emptyState
  @Builder
  emptyState() {
    Column({ space: 16 }) {
      BubuMascotBadge({ badgeSize: 84, expression: BubuExpression.surprised })
      Text('还没有照片\n回首页点「记录此刻」拍下第一张吧')
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 80 })
  }

  // 对照 featuredRow：横向滚动的叠放卡片。
  @Builder
  featuredRow() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(this.featured, (album: SystemAlbum) => {
          this.featuredCard(album)
        }, (album: SystemAlbum) => album.id)
      }
      .padding({ right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  // 对照 featuredCard
  @Builder
  featuredCard(album: SystemAlbum) {
    Column({ space: 8 }) {
      // 叠放卡片效果（对照 ZStack 上方两条错位白边）。
      Stack() {
        Stack()
          .width(134).height(16)
          .backgroundColor('#99FFFFFF')
          .borderRadius(14)
          .offset({ y: -5 })
        Stack()
          .width(142).height(16)
          .backgroundColor('#CCFFFFFF')
          .borderRadius(16)
          .offset({ y: -2 })
        // 封面
        Stack() {
          if (albumCover(album) !== undefined) {
            MediaThumbnail({ media: albumCover(album)!.media, cornerRadius: 18 })
              .width(150).height(150)
          } else {
            Stack() {
              Text(this.iconEmoji(album.icon)).fontSize(30)
            }
            .width(150).height(150)
            .backgroundColor('#1AF28C9E')
            .borderRadius(18)
          }
        }
        .width(150).height(150)
        .clip(true)
        .borderRadius(18)
        .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
      }
      .alignContent(Alignment.Top)
      .width(150).height(155)

      Row({ space: 5 }) {
        Text(this.iconEmoji(album.icon)).fontSize(11)
        Text(album.title)
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
        Blank()
        Text(`${albumCount(album)}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
      }
      .width(150)
    }
    .onClick(() => { this.detailAlbum = album; })
  }

  // 对照 albumSection：标题 + 两列网格卡片。
  @Builder
  albumSection(title: string, albums: SystemAlbum[]) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Grid() {
        ForEach(albums, (album: SystemAlbum) => {
          GridItem() {
            this.gridCard(album)
          }
        }, (album: SystemAlbum) => album.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(12)
      .width('100%')
      // 网格高度交给内容；用 layoutWeight 不可行（在 Scroll 内），按行估算。
      .height(Math.ceil(albums.length / 2) * 84)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 对照 gridCard
  @Builder
  gridCard(album: SystemAlbum) {
    Row({ space: 10 }) {
      Stack() {
        if (albumCover(album) !== undefined) {
          MediaThumbnail({ media: albumCover(album)!.media, cornerRadius: 12 })
            .width(52).height(52)
        } else {
          Stack()
            .width(52).height(52)
            .backgroundColor('#1AF28C9E')
            .borderRadius(12)
        }
      }
      .width(52).height(52)
      .clip(true)

      Column({ space: 3 }) {
        Text(album.title)
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(album.subtitle)
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .onClick(() => { this.detailAlbum = album; })
  }
}

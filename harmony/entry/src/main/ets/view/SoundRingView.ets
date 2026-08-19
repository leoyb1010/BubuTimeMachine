import { SoundRing, SoundRingClip } from '../models/AIArtifacts';
import { AIService } from '../services/AIService';
import { AudioPlayer } from '../services/media/AudioPlayer';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';

@Component
export struct SoundRingView {
  onBack: () => void = () => {};

  @State ring: SoundRing | null = null;
  @State history: SoundRing[] = [];
  @State loading: boolean = true;
  @State operation: string = '';
  @State errorText: string = '';
  @State audioPath: string = '';
  @State playing: boolean = false;
  @State progress: number = 0;

  aboutToAppear(): void {
    AudioPlayer.shared.setListener((progress: number, playing: boolean): void => {
      this.progress = progress;
      this.playing = playing;
    });
    this.load();
  }

  aboutToDisappear(): void {
    AudioPlayer.shared.setListener(null);
    AudioPlayer.shared.stop();
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹ 返回').backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown)
          .onClick(() => { AudioPlayer.shared.stop(); this.onBack(); })
        Blank()
        Text('声音年轮').fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text('       ')
      }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 7 }) {
            Text('听得见时间长大')
              .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            Text('只使用家里的真实原声，中性旁白只报年龄；不会克隆声音或补造内容。')
              .fontSize(13).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
          }.width('100%').padding(18).backgroundColor('#14DCC9FF').borderRadius(BubuRadius.card)

          if (this.loading) {
            Row({ space: 10 }) {
              LoadingProgress().width(24).height(24).color(BubuColor.primary)
              Text('正在读取声音年轮…').fontColor(BubuColor.secondaryText)
            }.width('100%').padding(20)
          } else if (this.ring) {
            this.ringContent(this.ring!)
          } else {
            this.emptyState()
          }

          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(13).fontColor(BubuColor.danger)
              .width('100%').padding(12).backgroundColor('#14DB3B47').borderRadius(BubuRadius.small)
          }

          if (this.history.length > 1) {
            Text('往期声音年轮').fontSize(14).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText).width('100%')
            ForEach(this.history, (item: SoundRing) => {
              Button(`${item.summary} · ${this.statusText(item.status)}`)
                .width('100%').height(48).backgroundColor(BubuColor.card).fontColor(BubuColor.warmBrown)
                .borderRadius(BubuRadius.small).onClick(() => { this.ring = item; this.audioPath = ''; })
            }, (item: SoundRing): string => item.id)
          }
        }.width('100%').padding(16)
      }.layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Text('还没有声音年轮').fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(AIService.shared.isConfigured
        ? '先同步至少约 3 分钟布布原声或家人留言；不会用静音凑时长。'
        : '请先在设置里连接家里的 AI 服务。')
        .fontSize(13).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
      Button(this.operation === 'drafting' ? '正在整理…' : '整理一圈声音')
        .width('100%').height(50)
        .enabled(AIService.shared.isConfigured && this.operation.length === 0)
        .backgroundColor(AIService.shared.isConfigured ? BubuColor.primary : BubuColor.softFill)
        .fontColor(AIService.shared.isConfigured ? Color.White : BubuColor.secondaryText)
        .borderRadius(BubuRadius.button).onClick(() => { this.createDraft(); })
    }.width('100%').padding(22).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
  }

  @Builder
  private ringContent(ring: SoundRing) {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text(ring.title).fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
        Text(`${ring.summary} · ${this.statusText(ring.status)}`).fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%')

      if (ring.status === 'ready' || ring.status === 'archived') {
        Column({ space: 10 }) {
          Button(this.operation === 'downloading' ? '正在取回音频…' : (this.playing ? '暂停' : '播放完整音频章'))
            .width('100%').height(52).enabled(this.operation.length === 0)
            .backgroundColor(BubuColor.deepRose).fontColor(Color.White).borderRadius(BubuRadius.button)
            .onClick(() => { this.play(ring.id); })
          Progress({ value: this.progress * 100, total: 100, type: ProgressType.Linear })
            .width('100%').color(BubuColor.deepRose)
        }.width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
      } else if (ring.status === 'rendering') {
        Row({ space: 10 }) {
          LoadingProgress().width(24).height(24).color(BubuColor.primary)
          Text('正在把原声轻轻接起来…').fontColor(BubuColor.warmBrown).layoutWeight(1)
          Button('刷新').height(44).onClick(() => { this.refreshStatus(ring.id); })
        }.width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
      }

      Text('这圈时间里的原声').fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
      ForEach(ring.clips, (clip: SoundRingClip) => {
        this.clipCard(clip, ring)
      }, (clip: SoundRingClip): string => clip.sourceId)

      if (ring.status === 'draft' || ring.status === 'failed') {
        Button(this.operation === 'rendering' ? '正在开始制作…' : '确认清单并开始制作')
          .width('100%').height(50).enabled(this.operation.length === 0)
          .backgroundColor(BubuColor.primary).fontColor(Color.White).borderRadius(BubuRadius.button)
          .onClick(() => { this.render(ring.id); })
      }
      if (ring.status === 'ready') {
        Button(this.operation === 'archiving' ? '正在归档…' : '收进档案')
          .width('100%').height(48).enabled(this.operation.length === 0)
          .backgroundColor(BubuColor.softFill).fontColor(BubuColor.warmBrown).borderRadius(BubuRadius.button)
          .onClick(() => { this.archive(ring.id); })
      }
    }.width('100%')
  }

  @Builder
  private clipCard(clip: SoundRingClip, ring: SoundRing) {
    Column({ space: 6 }) {
      Row() {
        Text(`${clip.ageYears} 岁`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.deepRose)
        Blank()
        Text(this.durationText(clip.durationSeconds)).fontSize(12).fontColor(BubuColor.secondaryText)
      }.width('100%')
      Text(clip.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
      if (clip.transcript.length > 0) {
        Text(`“${clip.transcript}”`).fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
      }
      if (ring.status === 'draft') {
        Button('只从本次清单移除')
          .height(44).width('100%').backgroundColor(BubuColor.softFill).fontColor(BubuColor.danger)
          .borderRadius(12).onClick(() => { this.removeClip(ring.id, clip.sourceId); })
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
    .padding(14).backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      if (!AIService.shared.isConfigured) return;
      this.ring = (await AIService.shared.latestSoundRing()) ?? null;
      this.history = await AIService.shared.soundRingHistory();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '声音年轮暂时无法读取';
    } finally {
      this.loading = false;
    }
  }

  private async createDraft(): Promise<void> {
    this.operation = 'drafting'; this.errorText = '';
    try { this.ring = await AIService.shared.createSoundRingDraft(); }
    catch (e) { this.errorText = e instanceof Error ? e.message : '暂时无法整理原声'; }
    finally { this.operation = ''; }
  }

  private async removeClip(id: string, sourceId: string): Promise<void> {
    if (this.operation.length > 0) return;
    this.operation = 'editing'; this.errorText = '';
    try { this.ring = await AIService.shared.removeSoundRingClip(id, sourceId); }
    catch (e) { this.errorText = e instanceof Error ? e.message : '暂时无法调整清单'; }
    finally { this.operation = ''; }
  }

  private async render(id: string): Promise<void> {
    this.operation = 'rendering'; this.errorText = '';
    try { this.ring = await AIService.shared.renderSoundRing(id); }
    catch (e) { this.errorText = e instanceof Error ? e.message : '声音年轮制作没有启动'; }
    finally { this.operation = ''; }
  }

  private async refreshStatus(id: string): Promise<void> {
    if (this.operation.length > 0) return;
    this.operation = 'refreshing'; this.errorText = '';
    try { this.ring = await AIService.shared.soundRingStatus(id); }
    catch (e) { this.errorText = e instanceof Error ? e.message : '暂时无法刷新状态'; }
    finally { this.operation = ''; }
  }

  private async archive(id: string): Promise<void> {
    this.operation = 'archiving'; this.errorText = '';
    try { this.ring = await AIService.shared.archiveSoundRing(id); }
    catch (e) { this.errorText = e instanceof Error ? e.message : '暂时无法归档'; }
    finally { this.operation = ''; }
  }

  private async play(id: string): Promise<void> {
    if (this.playing && this.audioPath.length > 0) {
      await AudioPlayer.shared.stop();
      return;
    }
    this.operation = 'downloading'; this.errorText = '';
    try {
      if (this.audioPath.length === 0) this.audioPath = await AIService.shared.downloadSoundRing(id);
      await AudioPlayer.shared.toggle(this.audioPath);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : '暂时无法播放声音年轮';
    } finally {
      this.operation = '';
    }
  }

  private statusText(status: string): string {
    if (status === 'draft') return '待确认清单';
    if (status === 'rendering') return '制作中';
    if (status === 'ready') return '可以播放';
    if (status === 'archived') return '已归档';
    if (status === 'failed') return '需要重试';
    return status;
  }

  private durationText(seconds: number): string {
    const total = Math.max(0, Math.round(seconds));
    return `${Math.floor(total / 60)}:${`${total % 60}`.padStart(2, '0')}`;
  }
}

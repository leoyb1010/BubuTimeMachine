import { ChildProfile, Entry } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { EntryWriter } from '../services/EntryWriter';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor } from '../theme/BubuTheme';
import { IdentityCard } from './IdentityCard';
import { ChildProfileView } from './ChildProfileView';
import { HealthHomeView } from './HealthHomeView';
import { promptAction } from '@kit.ArkUI';

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

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.entries = await AppDatabase.shared.fetchEntries(false);
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.profile) {
          IdentityCard({ profile: this.profile! })
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
        .onClick(() => { this.showRecord = true; })

        // 统计行
        Row({ space: 12 }) {
          this.statCard(`${this.entries.length}`, '个瞬间')
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
    Column({ space: 16 }) {
      Text('记录布布此刻').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      TextArea({ placeholder: '写一句关于布布的瞬间…', text: $$this.noteDraft })
        .height(120).borderRadius(12).backgroundColor('#F3F3F3')
      Button('保存')
        .width('100%').backgroundColor(BubuColor.primary)
        .onClick(async () => {
          const text = this.noteDraft.trim();
          if (text.length === 0) return;
          try {
            await EntryWriter.quickTextEntry(text, ServerConfig.shared.currentRole);
            this.noteDraft = '';
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

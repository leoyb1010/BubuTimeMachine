import { HomeView } from '../view/HomeView';
import { TimelineView } from '../view/TimelineView';
import { MilestonesView } from '../view/MilestonesView';
import { AIStudioView } from '../view/AIStudioView';
import { OnboardingView } from '../view/OnboardingView';
import { WhatsNewView } from '../view/WhatsNewView';
import { BubuGlassTabBar } from '../components/BubuGlassTabBar';
import { DesignGallery } from '../components/DesignGallery';
import { BubuColor } from '../theme/BubuTheme';
import { ThemeManager } from '../theme/ThemeManager';
import { WidgetRefresher } from '../theme/WidgetRefresher';
import { AppDatabase } from '../data/AppDatabase';
import { SyncEngine } from '../sync/SyncEngine';
import { CHANGELOG } from '../models/Changelog';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// MARK: - 根导航（对照 iOS App/RootTabView.swift + RootView）
// 首启引导（无 ChildProfile 时）→ 主界面：4 Tab（首页/时光/里程碑/魔法屋）+ 中央记录键。
// 时间胶囊收进「魔法屋(AIStudio)」，底栏保持轻量。升级后首次启动弹「更新内容」。
@Entry
@Component
struct RootPage {
  @State selection: number = 0;
  @State captureSignal: number = 0;          // 中央键 → HomeView 打开快速记录
  @State hasCompletedOnboarding: boolean = true;
  @State booted: boolean = false;
  @State showGallery: boolean = false;   // 恒 false，仅用于强制编译设计组件
  @State showWhatsNew: boolean = false;
  @StorageLink('themeTick') themeTick: number = 0;  // 主题切换驱动重绘

  private whatsNewStore: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    // 引导门槛：以是否已有布布档案为准（对照 iOS existing.isEmpty）。
    const profile = await AppDatabase.shared.fetchChildProfile();
    this.hasCompletedOnboarding = profile !== null;
    ThemeManager.shared.initialize(ctx);
    this.booted = true;
    // 回前台立刻补一轮同步 + 刷新服务卡片快照（对照 iOS scenePhase .active）。
    SyncEngine.shared.start();
    if (profile) WidgetRefresher.publishSnapshot(ctx, profile.birthday, profile.name);
    WidgetRefresher.reload();
    await this.maybeShowWhatsNew(ctx);
  }

  // 升级后首次启动弹更新内容；全新安装不弹（对照 iOS WhatsNewGate）。
  private async maybeShowWhatsNew(ctx: common.UIAbilityContext): Promise<void> {
    if (!this.hasCompletedOnboarding) return;
    try {
      this.whatsNewStore = await preferences.getPreferences(ctx, 'bubu_whatsnew');
      const seen = await this.whatsNewStore.get('lastSeenVersion', '') as string;
      const latest = CHANGELOG.length > 0 ? CHANGELOG[0].version : '';
      if (latest.length > 0 && seen !== latest) {
        this.showWhatsNew = true;
        await this.whatsNewStore.put('lastSeenVersion', latest);
        await this.whatsNewStore.flush();
      }
    } catch (e) {
      // 忽略：弹窗失败不影响主流程
    }
  }

  private async refreshWidget(): Promise<void> {
    WidgetRefresher.reload();
  }

  build() {
    Stack() {
      if (!this.booted) {
        // 启动占位（极短）。showGallery 恒为 false：仅为强制类型检查设计组件，运行期不展示。
        Stack() {
          Column().width('100%').height('100%').backgroundColor(BubuColor.cream)
          if (this.showGallery) {
            DesignGallery()
          }
        }.width('100%').height('100%')
      } else if (!this.hasCompletedOnboarding) {
        OnboardingView({ onComplete: () => {
          this.hasCompletedOnboarding = true;
          this.refreshWidget();
        }})
      } else {
        this.mainShell()
      }

      // 升级更新内容浮层
      if (this.showWhatsNew) {
        this.whatsNewOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  mainShell() {
    Stack() {
      // 页面区
      Stack() {
        if (this.selection === 0) {
          HomeView({ captureSignal: this.captureSignal })
        } else if (this.selection === 1) {
          TimelineView()
        } else if (this.selection === 2) {
          MilestonesView()
        } else {
          AIStudioView()
        }
      }
      .width('100%')
      .height('100%')

      // 奶油马卡龙玻璃胶囊底栏（对照 iOS BubuGlassTabBar）。中央键 = 回首页并触发快速记录。
      BubuGlassTabBar({
        selection: this.selection,
        tint: ThemeManager.shared.theme.primary,
        onCenterTap: () => {
          this.selection = 0;
          this.captureSignal = this.captureSignal + 1;
        }
      })
    }
    .alignContent(Alignment.Bottom)
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  @Builder
  whatsNewOverlay() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .onClick(() => { this.showWhatsNew = false; })
      Column() {
        Row() {
          Text('这次更新了什么').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Text('✕').fontSize(16).fontColor(BubuColor.secondaryText)
            .onClick(() => { this.showWhatsNew = false; })
        }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 })
        WhatsNewView()
        Button('好的，知道啦')
          .width('90%').height(46).backgroundColor(BubuColor.primary).fontColor(Color.White)
          .margin({ top: 8, bottom: 18 })
          .onClick(() => { this.showWhatsNew = false; })
      }
      .width('92%')
      .constraintSize({ maxHeight: '80%' })
      .backgroundColor(BubuColor.cream)
      .borderRadius(24)
    }
    .width('100%').height('100%')
  }
}

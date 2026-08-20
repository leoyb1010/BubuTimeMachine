import { HomeView } from '../view/HomeView';
import { TimelineView } from '../view/TimelineView';
import { GrowthHomeView } from '../view/GrowthHomeView';
import { AIStudioView } from '../view/AIStudioView';
import { OnboardingView } from '../view/OnboardingView';
import { WhatsNewView } from '../view/WhatsNewView';
import { BubuGlassTabBar } from '../components/BubuGlassTabBar';
import { BubuColor } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { ThemeManager } from '../theme/ThemeManager';
import { WidgetRefresher } from '../theme/WidgetRefresher';
import { AppDatabase } from '../data/AppDatabase';
import { SyncEngine } from '../sync/SyncEngine';
import { CHANGELOG } from '../models/Changelog';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SimpleModeView } from '../view/SimpleModeView';
import { BackDispatcher } from '../services/BackDispatcher';

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
  @State showWhatsNew: boolean = false;
  @State viewportW: number = 0;
  @StorageLink('themeTick') themeTick: number = 0;  // 主题切换驱动重绘
  @StorageLink('bubuTabBarVisible') tabBarVisible: boolean = true;
  @StorageLink('bubuSimpleMode') simpleMode: boolean = false;
  @StorageLink('bubuIntentDraft') @Watch('onIntentDraft') intentDraft: string = '';
  @StorageLink('bubuOpenEntryId') @Watch('onOpenEntryLink') openEntryId: string = '';

  private whatsNewStore: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 引导门槛：以是否已有布布档案为准（对照 iOS existing.isEmpty）。
    const profile = await AppDatabase.shared.fetchChildProfile();
    this.hasCompletedOnboarding = profile !== null;
    ThemeManager.shared.initialize(ctx);
    if (profile) {
      ThemeManager.shared.setBirthdayMonth(new Date(profile.birthday).getMonth() === new Date().getMonth());
    }
    this.booted = true;
    // 回前台立刻补一轮同步 + 刷新服务卡片快照（对照 iOS scenePhase .active）。
    SyncEngine.shared.start();
    await WidgetRefresher.publishCurrentSnapshot(ctx);
    WidgetRefresher.reload(ctx);
    await this.maybeShowWhatsNew(ctx);
    this.onIntentDraft();
    this.onOpenEntryLink();
  }

  private onIntentDraft(): void {
    if (this.intentDraft.trim().length === 0 || !this.booted || !this.hasCompletedOnboarding) return;
    this.selection = 0;
    this.captureSignal = this.captureSignal + 1;
  }

  private onOpenEntryLink(): void {
    if (this.openEntryId.trim().length === 0 || !this.booted || !this.hasCompletedOnboarding) return;
    this.selection = 0;
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
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await WidgetRefresher.publishCurrentSnapshot(ctx);
    WidgetRefresher.reload(ctx);
  }

  private isCompact(): boolean {
    return this.viewportW <= 0 || this.viewportW < 1500;
  }

  onBackPress(): boolean {
    if (this.showWhatsNew) {
      this.showWhatsNew = false;
      return true;
    }
    if (BackDispatcher.shared.handleBack()) return true;
    // 根 Tab 没有更深页面时交还系统：按返回退出/回桌面，不强制跳首页也不永久吞键。
    return false;
  }

  build() {
    Stack() {
      if (!this.booted) {
        // 数据库和主题初始化期间使用纯色启动底，不挂载任何不可达的演示组件。
        Column().width('100%').height('100%').backgroundColor(BubuColor.cream)
      } else if (!this.hasCompletedOnboarding) {
        OnboardingView({ onComplete: () => {
          this.hasCompletedOnboarding = true;
          this.refreshWidget();
          this.onIntentDraft();
        }})
      } else if (this.simpleMode) {
        SimpleModeView({ onExit: () => { this.simpleMode = false; } })
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
          HomeView({
            captureSignal: this.captureSignal,
            onOpenTimeline: () => {
              this.getUIContext().animateTo(BubuMotion.gentle, () => { this.selection = 1; });
            },
            onOpenMilestones: () => {
              this.getUIContext().animateTo(BubuMotion.gentle, () => { this.selection = 2; });
            }
          })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
        } else if (this.selection === 1) {
          TimelineView()
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
        } else if (this.selection === 2) {
          GrowthHomeView({ showBack: false })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
        } else {
          AIStudioView()
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
        }
      }
      .width('100%')
      .height('100%')
      .animation(BubuMotion.gentle)

      // 奶油马卡龙玻璃胶囊底栏（对照 iOS BubuGlassTabBar）。中央键 = 回首页并触发快速记录。
      if (this.tabBarVisible) {
        BubuGlassTabBar({
          selection: this.selection,
          tint: ThemeManager.shared.theme.primary,
          compact: this.isCompact(),
          onCenterTap: () => {
            this.selection = 0;
            this.captureSignal = this.captureSignal + 1;
          }
        })
      }
    }
    .alignContent(Alignment.Bottom)
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
    .onAreaChange((_old: Area, area: Area) => {
      const w = area.width as number;
      if (w > 0) this.viewportW = w;
    })
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

import { BigButton } from './BigButton';
import { ComingSoonView } from './ComingSoonView';
import { FlowLayout } from './FlowLayout';
import { ThemedBackground } from './ThemedBackground';
import { BubuMeshHero } from './BubuMeshHero';
import { PaperTextureOverlay } from './PaperTextureOverlay';
import { BubuGlassPanel } from './BubuLiquidGlass';
import { ThemeManager } from '../theme/ThemeManager';
import { NaturalCaptureBar } from '../view/NaturalCaptureBar';
import { TimelineEntryCard } from '../view/TimelineEntryCard';
import { Entry } from '../models/Models';
import { SyncState } from '../models/Enums';

// MARK: - 设计组件自检画廊
// 鸿蒙 ArkTS 会 tree-shake 未被引用的组件，导致其 build() 不被类型检查。
// 本画廊把设计系统里目前未在功能页直接引用的通用组件全部实例化一遍，
// 由 RootPage 在引导前的占位态引用（reachable），从而强制编译器完整类型检查它们，
// 保证「全部落地、严谨可编译」。运行期不展示（仅类型检查价值）。
@Component
export struct DesignGallery {
  @State theme: ThemeManager = ThemeManager.shared;
  private sampleEntry: Entry = {
    id: 'sample', happenedAt: 0, authorRole: '妈妈', note: '示例', syncState: SyncState.synced,
    isArchived: false, createdAt: 0
  };

  build() {
    Stack() {
      ThemedBackground({ theme: this.theme })
      Column({ space: 12 }) {
        BubuMeshHero()
        ComingSoonView({ title: '敬请期待', icon: '✨', message: '这个功能马上就来啦' })
        BigButton({ title: '记录此刻', onTap: () => {} })
        NaturalCaptureBar()
        TimelineEntryCard({ entry: this.sampleEntry })
        BubuGlassPanel({ thick: true }) {
          Text('玻璃面板')
        }
        FlowLayout({ spacing: 8 }) {
          Text('标签')
        }
      }
      PaperTextureOverlay()
    }
    .width('100%')
    .height('100%')
  }
}


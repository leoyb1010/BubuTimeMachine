# iOS ↔ HarmonyOS 文件对标映射基准

> 生成时间: 2024-06-14
> iOS 文件总数: 138 个 Swift
> Harmony 文件总数: 18 个 ETS

---

## 一、数据模型层 (Models/)

| iOS 文件 | 行数 | Harmony 对标 | 状态 | 备注 |
|---|---|---|---|---|
| Models/Enums.swift | 123 | models/Enums.ets (125行) | ✅ 已完成 | 注释明确对标iOS，值一致 |
| Models/AgeCalculator.swift | 63 | models/AgeCalculator.ets (91行) | ✅ 已完成 | |
| Models/Changelog.swift | 45 | models/Changelog.ets (34行) | ✅ 已完成 | |
| Models/Entry.swift | 53 | models/Models.ets (Entry) | ✅ 已完成 | |
| Models/FamilyMember.swift | 63 | models/Models.ets (FamilyMember) | ✅ 已完成 | |
| Models/FeedEvent.swift | 71 | models/Models.ets (FeedEvent) | ✅ 已完成 | |
| Models/FirstTime.swift | 29 | models/Models.ets (FirstTime) | ✅ 已完成 | |
| Models/GrowthMeasurement.swift | 34 | models/Models.ets (GrowthMeasurement) | ✅ 已完成 | |
| Models/HealthRecord.swift | 102 | models/Models.ets (HealthRecord) | ✅ 已完成 | |
| Models/Media.swift | 35 | models/Models.ets (Media) | ✅ 已完成 | |
| Models/Milestone.swift | 194 | models/Models.ets (Milestone) | ✅ 已完成 | |
| Models/TimeCapsule.swift | 30 | models/Models.ets (TimeCapsule) | ✅ 已完成 | |
| Models/VaccineRecord.swift | 39 | models/Models.ets (VaccineRecord) | ✅ 已完成 | |
| Models/VoiceNote.swift | 36 | models/Models.ets (VoiceNote) | ✅ 已完成 | |
| Models/Comment.swift | 30 | ❌ 缺失 | 🔴 待补充 | |
| Models/GrowthMovie.swift | 21 | ❌ 缺失 | 🔴 待补充 | AI成长电影数据 |
| Models/PendingDeletion.swift | 22 | ❌ 缺失 | 🔴 待补充 | 同步删除队列 |
| Models/VoiceMemo.swift | 32 | ❌ 缺失 | 🔴 待补充 | 与VoiceNote不同实体 |

**模型层完成度: 14/18 (78%)**

---

## 二、应用层 (App/)

| iOS 文件 | 行数 | Harmony 对标 | 状态 | 备注 |
|---|---|---|---|---|
| App/BubuTimeMachineApp.swift | 262 | entryability/EntryAbility.ets (50行) | ⚠️ 骨架 | 应用入口，生命周期 |
| App/RootTabView.swift | 66 | pages/RootPage.ets (64行) | ⚠️ 骨架 | 主导航结构 |
| App/AppEnvironment.swift | 150 | ❌ 缺失 | 🔴 待补充 | 环境配置/依赖注入 |
| App/BubuStorage.swift | 64 | data/AppDatabase.ets (496行) | ⚠️ 部分 | 首选项存储 |
| App/StorageMigrator.swift | 253 | ❌ 缺失 | 🔴 待补充 | 数据迁移 |
| App/SharedDefaults.swift | 77 | ❌ 缺失 | 🔴 待补充 | 共享偏好 |
| App/SharedModelContainer.swift | 40 | ❌ 缺失 | 🔴 待补充 | SwiftData容器 |
| App/BubuAppIntents.swift | 112 | ❌ 缺失 | 🔴 待补充 | 系统意图/快捷操作 |
| App/BubuActivityAttributes.swift | 28 | ❌ 缺失 | 🔴 待补充 | Live Activity |
| App/DebugQuickCapturePreviewView.swift | 23 | ❌ 缺失 | 🔴 待补充 | 调试预览 |

**应用层完成度: 2/10 (20%)**

---

## 三、设计系统层 (DesignSystem/)

| iOS 文件 | 行数 | Harmony 对标 | 状态 | 备注 |
|---|---|---|---|---|
| DesignSystem/BubuTheme.swift | 161 | theme/BubuTheme.ets (23行) | ⚠️ 骨架 | 主题token |
| DesignSystem/ThemeManager.swift | 179 | ❌ 缺失 | 🔴 待补充 | 主题切换管理 |
| DesignSystem/ThemedBackground.swift | 77 | ❌ 缺失 | 🔴 待补充 | 背景组件 |
| DesignSystem/BubuGlassTabBar.swift | 85 | ❌ 缺失 | 🔴 待补充 | 毛玻璃TabBar |
| DesignSystem/BubuLiquidGlass.swift | 35 | ❌ 缺失 | 🔴 待补充 | 液态玻璃效果 |
| DesignSystem/BubuMotion.swift | 86 | ❌ 缺失 | 🔴 待补充 | 动效token |
| DesignSystem/BubuHaptics.swift | 37 | ❌ 缺失 | 🔴 待补充 | 触觉反馈 |
| DesignSystem/BubuSound.swift | 51 | ❌ 缺失 | 🔴 待补充 | 音效 |
| DesignSystem/BubuExpression.swift | 56 | ❌ 缺失 | 🔴 待补充 | 表情动画 |
| DesignSystem/BubuMeshHero.swift | 55 | ❌ 缺失 | 🔴 待补充 | 3D网格动画 |
| DesignSystem/CeremonyAnimation.swift | 113 | ❌ 缺失 | 🔴 待补充 | 仪式感动画 |
| DesignSystem/PaperTextureOverlay.swift | 50 | ❌ 缺失 | 🔴 待补充 | 纸张纹理 |
| DesignSystem/BubuDateFormat.swift | 31 | ❌ 缺失 | 🔴 待补充 | 日期格式化 |
| DesignSystem/BigButton.swift | 53 | ❌ 缺失 | 🔴 待补充 | 大按钮组件 |
| DesignSystem/AppIconManager.swift | 32 | ❌ 缺失 | 🔴 待补充 | 图标管理 |
| DesignSystem/AppVersion.swift | 21 | ❌ 缺失 | 🔴 待补充 | 版本信息 |
| DesignSystem/WidgetRefresher.swift | 12 | ❌ 缺失 | 🔴 待补充 | 小组件刷新 |
| DesignSystem/String+Bubu.swift | 8 | ❌ 缺失 | 🔴 待补充 | 字符串扩展 |
| DesignSystem/MacaronComponents.swift | 159 | ❌ 缺失 | 🔴 待补充 | 马卡龙组件1 |
| DesignSystem/MacaronComponents2.swift | 159 | ❌ 缺失 | 🔴 待补充 | 马卡龙组件2 |
| **Components 子目录** | | | | |
| Components/BubuIdentityCard.swift | 319 | ❌ 缺失 | 🔴 待补充 | 身份卡片 |
| Components/MediaViewer.swift | 329 | ❌ 缺失 | 🔴 待补充 | 媒体查看器 |
| Components/MediaThumbnail.swift | 87 | ❌ 缺失 | 🔴 待补充 | 媒体缩略图 |
| Components/VoiceComponents.swift | 158 | ❌ 缺失 | 🔴 待补充 | 语音组件 |
| Components/MoodPicker.swift | 45 | ❌ 缺失 | 🔴 待补充 | 心情选择器 |
| Components/FlowLayout.swift | 48 | ❌ 缺失 | 🔴 待补充 | 流式布局 |
| Components/BubuMascotBadge.swift | 30 | ❌ 缺失 | 🔴 待补充 | 吉祥物徽章 |
| Components/ComingSoonView.swift | 28 | ❌ 缺失 | 🔴 待补充 | 即将推出占位 |

**设计系统完成度: 1/28 (4%)**

---

## 四、功能模块层 (Features/)

**全部缺失，0/55 (0%)**

### 4.1 Capture 拍摄模块 (7文件)
| iOS 文件 | 行数 | 优先级 |
|---|---|---|
| CaptureHomeView.swift | 940 | P0 核心入口 |
| CaptureModel.swift | 372 | P0 状态管理 |
| QuickCaptureSheet.swift | 497 | P0 快速拍摄 |
| OnThisDayView.swift | 147 | P1 当年今日 |
| DailyQuestion.swift | 56 | P1 每日问答 |
| HomeDestinations.swift | 65 | P1 导航定义 |
| CameraCaptureView.swift | 41 | P2 相机拍摄 |
| VideoCaptureView.swift | 43 | P2 视频拍摄 |

### 4.2 Timeline 时间线模块 (5文件)
| iOS 文件 | 行数 | 优先级 |
|---|---|---|
| EntryDetailView.swift | 522 | P0 详情页 |
| TimelineView.swift | 292 | P0 时间线主页 |
| TimelineEntryCard.swift | 124 | P0 卡片组件 |
| CommentComposeSheet.swift | 87 | P1 评论编写 |
| Reaction.swift | 114 | P1 反应交互 |

### 4.3 AI Studio 模块 (6文件)
| iOS 文件 | 行数 | 优先级 |
|---|---|---|
| GrowthMovieView.swift | 367 | P1 成长电影 |
| GrowthMoviePlayer.swift | 270 | P1 电影播放器 |
| AIStudioHomeView.swift | 259 | P1 AI工作室主页 |
| GrowthReportView.swift | 221 | P1 成长报告 |
| FirstPersonDiaryView.swift | 254 | P1 第一人称日记 |
| FamilyEnsembleView.swift | 142 | P2 家庭合集 |

### 4.4 Health 健康模块 (7文件)
| iOS 文件 | 行数 | 优先级 |
|---|---|---|
| HealthRecordSheet.swift | 581 | P1 健康记录表单 |
| WHOGrowthStandard.swift | 165 | P1 WHO生长标准 |
| HealthHomeView.swift | 183 | P1 健康主页 |
| GrowthCurveView.swift | 185 | P1 生长曲线 |
| VaccineView.swift | 247 | P1 疫苗视图 |
| VaccineQuickLogSheet.swift | 138 | P2 快速记录疫苗 |
| HealthKindDesign.swift | 74 | P2 健康类型设计 |
| VaccineSchedule.swift | 43 | P2 疫苗计划 |

### 4.5 Settings 设置模块 (9文件)
| iOS 文件 | 行数 | 优先级 |
|---|---|---|
| SettingsView.swift | 212 | P1 设置主页 |
| ExportView.swift | 234 | P1 数据导出 |
| ChildProfileView.swift | 188 | P1 孩子档案 |
| AdvancedSettingsView.swift | 188 | P2 高级设置 |
| MembersView.swift | 182 | P2 家庭成员 |
| YearbookView.swift | 172 | P2 年度相册 |
| VoiceArchiveView.swift | 204 | P2 语音存档 |
| AccountView.swift | 147 | P2 账户 |
| ThemeSettingsView.swift | 105 | P2 主题设置 |
| WhatsNewView.swift | 138 | P2 更新说明 |

### 4.6 其他功能模块
- **Capsule 时光胶囊** (4文件): CapsuleComposeView(248), CapsuleHomeView(207), CapsuleUnlockView(250), CapsuleRecoveryView(157)
- **Album 相册** (3文件): AlbumHomeView(210), AlbumDetailView(55), SystemAlbum(92)
- **Milestones 里程碑** (3文件): MilestonesHomeView(229), MilestoneSheets(265), BubuConstellationView(210)
- **Story 故事** (3文件): BubuStoryReaderView(186), BubuStoryView(115), StoryChapter(67)
- **NaturalCapture 自然拍摄** (3文件): NaturalCaptureReviewSheet(397), NaturalCaptureBar(230), NaturalCaptureRouter(187)
- **Onboarding 引导** (1文件): OnboardingView(205)
- **Feed 家庭动态** (1文件): FamilyFeedView(130)

---

## 五、服务层 (Services/)

### 5.1 同步服务 (Sync/)
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| SyncEngine.swift | 1177 | sync/SyncEngine.ets (145行) | ⚠️ 骨架 |
| VaccineLegacyMigrator.swift | 39 | ❌ 缺失 | 🔴 |

### 5.2 网络服务 (Networking/)
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| PocketBaseClient.swift | 1012 | ❌ 缺失 | 🔴 核心API客户端 |
| DTOs.swift | 230 | services/DTOs.ets (94行) | ⚠️ 部分 |
| AccountService.swift | 139 | services/AccountService.ets (117行) | ⚠️ 部分 |
| APIClient.swift | 71 | services/APIClient.ets (103行) | ⚠️ 部分 |
| ServerConfig.swift | 97 | services/ServerConfig.ets (100行) | ✅ 已完成 |
| MockAPIClient.swift | 97 | ❌ 缺失 | 🔴 |

### 5.3 AI服务 (AI/)
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| BubuAIService.swift | 143 | services/AIService.ets (54行) | ⚠️ 骨架 |
| NaturalCaptureDTO.swift | 206 | ❌ 缺失 | 🔴 |
| MockAIService.swift | 115 | ❌ 缺失 | 🔴 |
| AIService.swift | 16 | ❌ 缺失 | 🔴 |

### 5.4 媒体服务 (Media/)
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| MediaStore.swift | 229 | services/MediaStore.ets (58行) | ⚠️ 骨架 |
| AudioRecorder.swift | 122 | services/AudioRecorder.ets (88行) | ⚠️ 部分 |
| ArchiveExporter.swift | 230 | ❌ 缺失 | 🔴 |
| YearbookExporter.swift | 192 | ❌ 缺失 | 🔴 |
| PhotoAnalyzer.swift | 162 | ❌ 缺失 | 🔴 |
| ThumbnailProvider.swift | 173 | ❌ 缺失 | 🔴 |
| AudioPlayer.swift | 65 | ❌ 缺失 | 🔴 |

### 5.5 安全服务 (Security/)
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| CapsuleCrypto.swift | 132 | ❌ 缺失 | 🔴 加密 |
| CapsuleVault.swift | 93 | ❌ 缺失 | 🔴 保险库 |
| CapsuleRecovery.swift | 70 | ❌ 缺失 | 🔴 恢复 |
| KeychainStore.swift | 78 | ❌ 缺失 | 🔴 钥匙串 |

### 5.6 其他服务
| iOS 文件 | 行数 | Harmony 对标 | 状态 |
|---|---|---|---|
| EntryWriter.swift | 60 | services/EntryWriter.ets (102行) | ✅ 已完成 |
| BubuActivityController.swift | 79 | ❌ 缺失 | 🔴 Live Activity |
| ReminderScheduler.swift | 90 | ❌ 缺失 | 🔴 提醒调度 |
| LocationService.swift | 125 | ❌ 缺失 | 🔴 位置服务 |

**服务层完成度: 4/27 (15%)**

---

## 六、总体完成度统计

| 模块 | iOS文件数 | Harmony已实现 | 完成度 |
|---|---|---|---|
| Models | 18 | 14 | 78% |
| App | 10 | 2 | 20% |
| DesignSystem | 28 | 1 | 4% |
| Features | 55 | 0 | **0%** |
| Services | 27 | 4 | 15% |
| **总计** | **138** | **21** | **15%** |

---

## 七、优先级建议

### P0 核心路径（最小可用产品）
1. 补齐数据模型缺口（Comment/GrowthMovie/PendingDeletion/VoiceMemo）
2. Capture 拍摄模块（CaptureHomeView + QuickCaptureSheet）
3. Timeline 时间线（TimelineView + EntryDetailView）
4. 基础设计系统（BubuTheme + ThemedBackground + BubuMotion）

### P1 重要功能
- AI Studio 成长电影
- Health 健康记录
- Settings 设置页
- 完整网络层（PocketBaseClient）

### P2 增强功能
- Capsule 时光胶囊
- Album 相册
- Story 故事
- NaturalCapture 自然拍摄

---

## 八、技术债务标记

- [ ] Harmony Models.ets 将多模型合并在单文件，需考虑是否拆分
- [ ] SyncEngine 仅145行骨架，iOS 1177行完整实现
- [ ] PocketBaseClient 完全缺失，这是核心API客户端
- [ ] DesignSystem 动效/主题系统几乎空白
- [ ] Features 55个页面全部缺失

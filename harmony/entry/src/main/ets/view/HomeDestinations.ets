// MARK: - 首页导航目的地（对照 iOS Features/Capture/HomeDestinations.swift）
// iOS 用 NavigationStack + navigationDestination(for:) 路由；
// 本切片沿用 HomeView 既有的 @State 索引式导航（RootPage 以 tab index 切换，HomeView 内部以
// HomeRoute 状态切面板）。这里把可达目的地枚举出来，作为 HomeView 内部路由的契约。
export enum HomeRoute {
  home,            // 仪表盘首页
  record,          // 记录此刻（快速记录面板）
  profile,         // 布布资料
  health,          // 布布健康
  growth,          // 成长曲线
  settings,        // 设置
  syncCenter,      // 同步与备份状态
  album,           // 相册 / 照片墙
  timeline,        // 时光轴
  ssdIntake,       // 家庭 mini / 移动硬盘待确认候选
  photoInbox,      // 系统相册待收照片
  onThisDay,       // 那年今日
  naturalCapture,  // 一句话智能记录
  entryDetail      // 单条记录详情
}

// MARK: - 全屏查看器路由（相册体系共用，对照 iOS MediaViewerRoute）
export interface MediaViewerRoute {
  initialMediaID: string;
}

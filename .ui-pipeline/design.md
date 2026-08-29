# Design Direction

## Chosen direction

- Mode: Operate（日常记录/回看）为主，Experience（胶囊/里程碑/作品）为辅。
- Concept spine: 一本会生长的家庭档案。
- First-read object: iPhone 是“今天的布布 + 记录此刻”；iPad 是同一档案在系统侧栏和宽屏内容列中展开。
- Signature: 保存从系统记录附件进入，最终回到时光卡；真实照片和时间承担主视觉。

## System

- Navigation: iOS 26 原生 Liquid Glass Tab、滚动收缩、bottom accessory；iPad `sidebarAdaptable`。
- Spatial thesis: 手机单列、每屏一个主体；平板以可用宽度决定列数，正文 700–920pt 收口，不按设备型号写死。
- Material: 暖纸面和真实素材；Glass 只用于系统导航、附件和弹层。
- Typography: 系统字体；首页证件卡在手机收为紧凑 Living Cover，完整信息留给宽屏/档案页。
- Motion: quick/gentle/smooth/ceremony/breathe 五级 token；减少动态时移除位移与循环。
- Anti-defaults: 不做幼儿九宫格，不让玻璃铺满页面，不让浮动 AI 球遮挡业务操作。

## Responsive behavior

| Width/state | Navigation | Content |
|---|---|---|
| iPhone / compact | Bottom Tab + record accessory | Single column, compact living cover |
| iPad narrow split | Same compact path | Single column, no clipped controls |
| iPad regular | Adaptive top/sidebar | 700–920pt reading columns, adaptive grids |
| iPad landscape/window | Sidebar available, keyboard shortcuts | Higher density without stretching text |
| iOS 27 resizable | Same width-driven rules | Xcode 27 shadow build validates continuous resize |

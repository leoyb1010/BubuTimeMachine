# UI Proof

## Verification scope

- Release level: Level 3（跨端家庭数据产品）
- Routes / screens: 同步中心、照片收件箱、移动硬盘候选、成长中心、问问布布、布布周报、声音年轮、三动作姥姥模式、真实 PDF 年册、三版式分享卡、持久哄睡计时、手机相框和时光详情媒体分页
- Viewports / devices: HUAWEI Pura X Max 典藏版，HarmonyOS 7.0.0 / API 26；仅手机范围
- Runtime baseline: `efd1c87` 对应签名 HAP 于 2026-08-19 17:24 安装成功，EntryAbility 为 FOREGROUND、进程存在、启动日志无崩溃

## Evidence

- Screenshots / visual diffs: 已核对真机里程碑页面和首次仪式弹窗；截图含家庭隐私，仅留本机证据，不提交仓库
- Storybook stories and tests: 不适用 ArkUI；当前 63 个 Node 契约/逻辑测试通过
- End-to-end interactions: 安装、启动、前台 Ability 和首屏渲染已通过；当前新增横滑与 2.11 信息架构待下次真机交互回归
- Accessibility checks: 设计契约已记录，运行验证待补
- Console / network checks: API 26 unsigned HAP 构建成功；已获取一次真机启动日志且无崩溃
- Performance checks: 待补
- Reduced-motion check: 待补

## Snapshot decisions

- Intentional baseline changes: 保留既有“家庭绘本 × 成长档案”视觉方向，不另起设计语言
- Rejected changes: 用 emoji 替代正式系统图标、用占位页计入追平

## Remaining risk

- Known issues: Live View TIMER 权益未知；编译警告仍以 RDB/系统 API 的“可能抛异常”和设备能力提示为主
- Deferred work: 当前代码的照片左右翻页、放大后平移、首页/魔法屋/设置/姥姥模式与移动硬盘候选需要下一次真机回归
- Visual verification outstanding: 是（当前最新代码尚未重新安装）

**当前状态：HOLD** — 旧基线已完成真机安装与启动；当前最新代码通过 63 项测试和 API 26 构建，但尚缺照片横滑等新增交互的真机复验。

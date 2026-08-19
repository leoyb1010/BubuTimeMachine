# UI Brief

## Outcome

- User-visible outcome: HarmonyOS 端追平 iOS 2.11.0 的业务能力，并用鸿蒙原生交互承载卡片、意图、穿戴与跨设备能力。
- Success signal: 同一家庭数据下，核心任务结果与 iOS 一致；手机、平板、折叠屏和穿戴端均有真实运行证据。

## Users and situation

- Primary users: 家庭成员，包含需要大字、低认知负担操作的长辈。
- Job to be done: 可靠记录、回看、搜索、分享孩子成长资料，且不因断网、杀进程或换设备丢失。
- Environment and devices: HarmonyOS 手机、平板、折叠屏、鸿蒙电脑与华为穿戴设备。

## Scope

- In scope: iOS 全部用户能力、鸿蒙原生替代能力、响应式布局、无障碍、深色模式和关键状态。
- Out of scope: 与家庭成长记录无关的通用社交或营销功能。

## Facts and constraints

- Product facts: 已有 ArkUI 马卡龙视觉系统、布布吉祥物、PocketBase + FastAPI 共用后端和 122 个 ETS 文件。
- Technical constraints: API 26；离线优先；不得提交签名、账号或家庭数据；不能用页面存在替代真实链路验收。
- Accessibility / localization constraints: 中文优先；支持系统字体缩放、关怀模式、深浅色、高对比和减少动效。

## References

- Product references: iOS `main` 2.11.0、`harmony/PARITY_MATRIX.md`。
- Visual references: iOS 当前产品截图与仓库既有 BubuTheme/MacaronComponents；不另起无关视觉方向。

## Assumptions and open decisions

- Assumptions: 业务能力等价优先于控件逐像素复制，系统能力采用鸿蒙推荐交互。
- Open decisions: Live View、Wear Engine 等受限权益以开发者后台实际开通结果为准。

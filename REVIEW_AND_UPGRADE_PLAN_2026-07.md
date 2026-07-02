# 布布时光机 · 全面 Review 与上线升级总计划

> 生成日期：2026-07-02 ｜ 审查基线：main `136cdc6`（含工作区未提交改动）
> 审查方式：4 个并行深度审查（iOS 核心层 / iOS UI 层 / 鸿蒙端 / 服务端）+ 主控独立核实（clean build 实测、模拟器截图实测、关键 bug 逐行复核）
> 本文档给执行 AI（Opus）直接干活用：所有 bug 带 `文件:行号`，所有阶段带验收标准。
> **执行顺序就是章节顺序：Phase 0 → Phase 8。不要跳阶段。**

---

## 0. 给执行者的基线事实与工作纪律（先读这个）

### 0.1 关键事实（已实测核验）

| 事实 | 状态 |
|---|---|
| **iOS clean build** | ❌ **失败**。HEAD `136cdc6` 本身编译不过（见 P0-1），当前 main 不可发版 |
| iOS 单元测试 | ❌ 因编译失败全部无法运行 |
| 鸿蒙 clean build | ✅ 通过（hvigor assembleHap，HAP 产物正常） |
| 工作区 | 有 21 个文件未提交改动（iOS 里程碑去重 WIP + 鸿蒙同步改动），也编译不过 |
| CI | 存在（`.github/workflows/ci.yml`），但当前必红且未阻断合并 |
| 版本 | iOS 1.2.0 (build 2026061312)，鸿蒙对齐 1.2.0 流程 |
| 服务器 | PocketBase + FastAPI(DeepSeek)，写死 `https://bubu-api.leoyuan.top` / `bubu-ai.leoyuan.top` |
| 账户现状 | 单家庭共享数据；用户名+密码+家庭码注册；家庭码 `YUANCHENXI` 硬编码在客户端 `AccountService.swift:15`，仅客户端校验 |
| UI 现状 | 马卡龙奶油视觉完成度高，深浅色均适配良好（模拟器实测截图确认）；4 tab（首页/时光/星座/魔法屋）+ 中央记录键 |

### 0.2 验证命令（每个 Phase 完成必须跑）

```bash
cd /Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine
xcodegen generate
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean test 2>&1 | grep -E ": error:|BUILD SUCCEEDED|BUILD FAILED|TEST"

# 鸿蒙
cd harmony
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH="$NODE_HOME/bin:$JAVA_HOME/bin:$PATH"
./hvigorw clean --no-daemon && ./hvigorw assembleHap --mode module -p product=default --no-daemon

# 服务端
cd server/ai && .venv/bin/python -m pytest tests/
```

### 0.3 工作纪律

1. **clean build 才可信**；改 `project.yml` 后必须 `xcodegen generate`。
2. 每个独立修复一个 commit，中文 message。
3. **凡是涉及同步/加密/DTO 的改动，两端（iOS+鸿蒙）必须同步改并做双端互通验证**（一端写→另一端拉→内容/文件/解密全对）。
4. 不提交 `server/ai/.env`、PocketBase 二进制、`pb_data/`。
5. 修 bug 先补回归测试（能补则补），再改实现。

---

## 1. 执行摘要

**整体评价**：工程素养高于个人项目平均水平（离线优先架构、协议先行 DI、动效 token 化、reduceMotion 纪律、口语化文案、文件格式嗅探、迁移器安全纪律都很扎实），但存在四类系统性问题：

1. **当前 main 编译失败**（Widget target 引用不可见符号）——一切之前先修这个。
2. **同步层一致性缺陷成串**：游标日期格式与 PocketBase 不兼容导致**同日远端变更永久漏拉**（P0）；删除同步只覆盖 1/13 集合；nil 字段永不上行且会被"弹回"；冲突策略是"最后推送者赢"。这些共同解释了仓库里为什么会出现 `debugForceUploadAllLocalDataToCloud` 这类补救工具。
3. **鸿蒙端与 iOS 互通实际是断的**：6 个 P0 断点（iOS 文件在鸿蒙全部下载不了、insert 主键冲突中断整轮同步、里程碑点亮被吞、胶囊 salt 大小写不一致导致 iOS 解不开鸿蒙的信、基线导入自动清库/死锁、删除不传播）。**当前"双向收敛"只存在于注释里。**
4. **服务端安全裸奔**：PocketBase 默认开放注册 + "登录即全权"规则 + 服务器地址和家庭码都随源码公开在 GitHub → 任何人可注册账号读写删全家数据；localId 唯一索引实际不存在（PB v0.23+ 忽略字段级 unique）；备份方案会备出损坏的 SQLite。
5. **适老化短板**：全 App 288 处硬编码字号、零 Dynamic Type 支持——"姥姥能用 = 验收标准"当前不成立。

**升级路线**（细节见 Phase 0-8）：止血修
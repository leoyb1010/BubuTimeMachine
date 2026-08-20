# 布布时光机 · HarmonyOS 手机端

iOS 2.11.0 的鸿蒙原生实现，使用 ArkTS / ArkUI，与 iOS 共用 PocketBase + FastAPI 自托管后端。

本工程只支持 HarmonyOS 手机。平板、折叠屏、鸿蒙电脑和穿戴端不在本次范围，`module.json5` 仅声明 `phone`。

## 当前结论

- API 26 代码能力已完成追平；逐项状态和真机验收边界见 [`PARITY_MATRIX.md`](PARITY_MATRIX.md)。
- 本地 `68` 个逻辑/契约测试通过，API 26 unsigned HAP 构建通过。
- 2026-08-19 已在 HUAWEI Pura X Max（HarmonyOS 7.0.0 / API 26）完成一次签名安装、前台启动和无崩溃日志验证；当前新增横滑与 2.11 信息架构仍待下次真机交互回归。
- Live View 使用 TIMER 原生实况窗；未获华为场景权益时自动降级为持续通知。

## 已实现能力

- 记录：文字、照片、视频、语音、真实一次定位、发生时间编辑、追加媒体和家人回应。
- 时光轴：拍摄/记录时间双排序、RDB 200 条触底分页、全文搜索和语义搜图。
- 数据：RDB 幂等迁移、全部集合双向同步、服务器游标、墓碑删除、退避重试、WorkScheduler 后台恢复。
- 媒体：文件流式上传、系统落盘下载、缩略图、人脸数量、认布布提示、端侧物体标签、照片收件箱、移动硬盘候选确认、详情多媒体左右翻页、鉴权补拉、照片缩放平移、存相册与 Share Kit 分享。
- 成长：健康、持久哄睡计时、WHO 插值、成长曲线、疫苗、里程碑、第一次和旧数据迁移。
- 创作：第一人称日记、用户收录式成长绘本、家人合奏、成长报告、周报、问答、声音年轮和服务端成长电影成片。
- 传承：v3 E2E 时间胶囊（文字+语音）、24 词恢复码、开放档案 ZIP、真实 PDF 年册、三版式分享卡。
- 鸿蒙原生：2×2/2×4 服务卡片、最近照片封面、Share Kit、PDF Kit、InsightIntent 参数记录、Live View、系统备用图标。
- 体验：姥姥三动作模式、系统/星夜深色、核心屏幕朗读语义、旧手机全屏相框模式。

## 构建与检查

要求：DevEco Studio 26.0.0+、HarmonyOS API 26 SDK、JBR 21。

```bash
cd harmony
./scripts/check-repository-hygiene.sh
NODE_OPTIONS=--no-warnings=MODULE_TYPELESS_PACKAGE_JSON node --test tests/*.test.mjs
./scripts/build-local.sh
```

产物：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

工程默认不带签名。真机安装前在 DevEco Project Structure 配置本机自动签名；证书、私钥、口令和绝对路径不得提交。

## 真机验收清单

1. 旧 HAP 覆盖安装，确认档案、媒体、胶囊、健康、绘本收录不丢失。
2. 离线新增/修改/删除，再联网；iOS 与鸿蒙交叉操作不复活、不误删。
3. 大文件弱网上传、杀进程、重启后恢复；远端媒体系统下载可播放。
4. 麦克风、相机、图库、定位权限拒绝/再次授权；录音中断不丢文件。
5. 2×2/2×4 服务卡片的照片、刷新和点击；7 套主题图标与生日图标刷新。
6. TIMER 权益下验证录音、哄睡和临近胶囊 Live View；无权益验证通知降级。
7. 小艺平台登记 `BubuOpenApp`、`BubuRecordMoment`，验证参数原话进入确认页。
8. 浅色/深色、系统大字、屏幕朗读焦点顺序；保留截图、日志和设备/系统版本。

## 安装到当前设备

```bash
hdc list targets -v
./scripts/run-on-harmony-device.sh
```

多设备时：

```bash
./scripts/run-on-harmony-device.sh <target>
```

打开一条显示 `x / N · 左右滑动` 的多媒体时光后，可执行真机页码断言：

```bash
./scripts/verify-media-swipe.sh <target>
```

## 架构对照

| iOS | HarmonyOS |
|---|---|
| SwiftUI | ArkUI |
| SwiftData | RelationalStore |
| UserDefaults / AppStorage | Preferences / AppStorage |
| WidgetKit | Form Kit |
| App Intents | InsightIntent |
| Live Activity | Live View TIMER |
| UIKit/ImageRenderer PDF | ArkGraphics2D + PDF Kit |
| Share Sheet | Share Kit |

后端 collection、`localId` 幂等键、软删除字段和 AI API 契约保持跨端一致。

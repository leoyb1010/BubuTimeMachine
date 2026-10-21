# 家庭学习服务部署与恢复

本功能在 `2.23.0` 中新增。默认关闭，部署代码不会开始扫描、调用模型、写入时光或发布课程。原生入口复用当前家庭的 PocketBase 会话。

## 数据链路

1. 家人从群里把老师的照片、视频保存到 iPhone 照片库。
2. 现有第二大脑从 iCloud Photos 同步并完成其 Gemini/OCR 解析。
3. 学习 worker 只读该资料库，按教学内容筛选候选。按 PhotoKit UUID 保留每次保存事件，按文件 hash 复用字节；同视频再次保存不丢失新日期。
4. 新视频做完整音轨转写，并抽取有时间码的画面；继续使用第二大脑现有 `gemini-3.8-flash-high`、`high` 配置。不会使用伴生服务的其他模型回退。
5. 自动生成待核对课程。原声问题、原声答案、图像资源都由已验证的来源片段生成。家人逐项核对并确认授课日期后，孩子才能开始课程及近7/30天重温。
6. 已通过人工归属确认的照片可通过独立的时光同步开关入库。第二大脑历史自动人脸匹配结果仍是候选，不因置信度高而成为人工确认，也不会自动认人。

`LEARNING_INBOX` 是已授权的“布布幼儿园”备用入口。自动导入主路径为 iCloud；不要求家人再发一遍时光。保存时间、文件修改时间均不是授课日期，界面会要求确认。

## 配置与启动

在 AI 服务现有 `.env` 中设置 `.env.example` 的 `LEARNING_*` 项。不要把该文件、原件或第二大脑凭据加入仓库。

- `LEARNING_STATE_DIR`：项目独立的持久目录，必须位于外置盘挂载可用或稳定的本地应用支持路径。不能放在版本化 release 目录。
- `LEARNING_FAMILY_ID` / `LEARNING_CHILD_ID`：分别为当前家庭ID和 ChildProfile 的 `localId`。其他模块的家庭配置必须一致。
- `LEARNING_REVIEWER_USER_IDS`：明确允许核对/开放课程的 PB 用户ID列表。
- `LEARNING_BRAIN_ROOT`：现有第二大脑资料库根目录。
- `LEARNING_BRAIN_PYTHON`：能运行第二大脑代码的解释器；其现有代码要求 Python 3.12+，不能直接沿用本服务的 Python 3.11 venv。
- `LEARNING_SINCE_DATE`：首轮候选保存时间起点，格式 `YYYY-MM-DD`。没有可信保存时间的素材仍作为不确定候选保留。
- `LEARNING_TIMELINE_ENABLED` 默认 `false`。开启前配置作者用户/角色和精确 subject ID，并核对作者仍属于该家庭。

代码部署、签名、域名和账户权限核对完成后，显式设置 `LEARNING_ENABLED=true`。启动现有 AI 服务，再使用：

```sh
./server/ai/start_learning_worker.sh --once
```

核对状态后可将 `server/ops/com.bubu.learning-worker.plist.example` 替换为实际部署路径并安装。worker 使用进程锁和持久任务队列，每轮最多处理10个任务，30秒后再检查；不在 HTTP 请求线程调用 Gemini。现有服务不需要复制模型密钥。

网页会话使用 Secure / HttpOnly / SameSite=Strict Cookie，正式域名必须 HTTPS。普通 HTTP 回环地址不适合直接测试 Cookie 登录。原生初始请求携带 PB Bearer，后续同源请求使用受保护会话。

## 验收

- 查看学习页的同步状态、日期候选、完整转写和原片；非教学、照护素材不应被强行出题。
- 核对后半段视频也有转写，原声按钮直接播放老师的问题或词语，不先播放介绍。
- 核对多色回答保留整个组合；选项图像确实对应引用时间点。
- 人工修订转写、改变日期或移除来源后，旧课程立即撤回，旧确认不能再次发布。
- 同一素材不同保存事件保留两个来源；删除或隐藏的时光不被自动恢复。
- 撤回用户家庭权限后，原片、派生音频、解析检索全部拒绝访问。
- 互动记录只记录选择、表达尝试和参与，不作为儿童能力或掌握程度分数。

## 备份与恢复

在现有备份配置中填写 `LEARNING_STATE_DIR`。`run_scheduled_backup.sh` 将其交给 `backup_pb_data.sh`，后者在 restic 快照前创建 `MIRROR_DIR/learning`：在线 SQLite 备份、原始字节和校验过的派生产物一起保存。学习备份失败时不会更新共享成功时间戳。

独立导出也可运行：

```sh
cd server/ai
python3 -m learning.backup --source /ABSOLUTE/learning-state --destination /ABSOLUTE/learning-export
```

目标必须是专用空目录或有合法标记的已有学习备份目录。恢复时先停止学习 worker，将备份还原到新的项目状态目录，验证 SQLite 完整性及原件/派生文件 hash，再切换 `LEARNING_STATE_DIR`。第二大脑个人资料库和模型凭据不包含在该导出中。

## 回退

停止学习 worker，并设 `LEARNING_ENABLED=false`、`LEARNING_TIMELINE_ENABLED=false`，再重启 AI 服务。保留学习状态目录和原件，不删除已写入的家人记录。需要回退原生版本时遵循现有 SwiftData 升级备份流程；本轮未新增或修改 SwiftData `@Model`。

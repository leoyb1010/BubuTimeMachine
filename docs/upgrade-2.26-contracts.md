# 2.25.1 / 2.26 / 2.27 接口约定

服务端与 App 并行开发时以本文件为准。前缀均为 `/learning/api`，鉴权与现有接口一致（`_scope` + `timeline.authorize`），
写操作需要 CSRF 头（与现有 POST 一致）。JSON 用 snake_case，App 端 `convertFromSnakeCase` 解码。
`OnlineTimelineItem` 指现有 `online-timeline` 返回的单条结构（`OnlineTimeline.public`）。

## 稳定性（2.25.1）

- 第二大脑相关接口在快照不可用或拿锁超时（约 3 秒）时返回 **503**，`detail` 为
  `"家里的服务器暂时读不到素材库，请稍后重试。"`，不再无限挂起。
- `GET /health/deep`（`main.py`，仅本机回环可访问，外部访问返回 404）：
  `{"ok": bool, "learning_store": bool, "brain_library": bool, "worker_heartbeat_age_s": int|null, "snapshot_age_s": int|null}`。
  内部用带超时的子进程/线程探测外接盘，探测本身不会卡住请求线程。

### `GET status` — 家里服务器状态（设置页用）
```json
{"ok": true, "learning_store": true, "brain_library": true,
 "worker_alive": true, "worker_heartbeat_at": "2026-10-22T13:00:00+08:00",
 "snapshot_at": "…", "captions_pending": 1, "voices_pending": 551,
 "backup_at": "2026-10-22T03:17:00+08:00", "items": 2518, "checked_at": "…"}
```
任何字段取不到时为 `null`；不包含路径、主机名、密钥。

## 能力（2.26）

### `POST ask` — 布布问答
请求 `{"question": "她第一次去海边是什么时候？"}`（1–200 字）。
```json
{"answer": "2025 年 7 月 12 日在……（可为 null，模型不可用时）",
 "citations": [{"id": "<24hex>", "note": "第一次踩到沙子"}],
 "items": [OnlineTimelineItem, …],
 "semantic": true, "model_used": true}
```
`items` 最多 12 条，按相关度排序；`citations[].id` 必在 `items` 里。模型不可用时 `answer=null, model_used=false`，仍返回检索到的素材。
`answer` 里用 `[n]` 内联标注引用，`n` 为 `citations` 数组的 1 起始下标（例：`2025 年 7 月在舟山第一次看海[1]，后来又去了一次[2]。`）；
服务端按过滤后的 `citations` 重新编号，越界或指向被剔除引用的标记会被删掉，App 可放心按下标取 `citations[n-1]`。

### `GET words` — 语言成长线
```json
{"months": [{"month": "2026-03", "new_words": ["爸爸", "苹果"], "total": 12}],
 "firsts": [{"word": "爸爸", "item_id": "<24hex>", "voice_id": "<id>|null",
             "captured_at": "…", "text": "爸爸抱"}],
 "source_count": 79, "pending": 551}
```
数据来自声音档案中已确认为孩子说的话（voices ready）。`total` 为截至该月累计不同词数。

### `GET places`
```json
{"items": [{"name": "上海市·世纪公园", "short": "世纪公园", "city": "上海市", "count": 34,
            "cover_url": "/learning/api/online-timeline/<id>/preview?size=thumb&revision=…",
            "item_ids": ["…"], "first_day": "2025-04-03", "last_day": "2026-09-30"}]}
```
`item_ids` 最多 60 个，按时间倒序。没有经纬度，App 端用 `CLGeocoder` 按 `name` 地理编码并缓存。

### `GET events?start=&end=`
```json
{"items": [{"id": "<album id>", "title": "海边的周末", "story": "……", "day": "2025-07-12",
            "place": "舟山", "count": 18,
            "cover_url": "/learning/api/online-timeline/<id>/preview?size=large&revision=…",
            "item_ids": ["…"]}]}
```
只返回至少含 3 条布布素材的自动事件；`item_ids` 只含当前时光里可见的素材；按 `day` 倒序。

### 认一认 撤销 / 批量
- `POST recognition/{fid}` 增加 `{"decision": "undo"}`：删除布布侧的决定，恢复为第二大脑默认。
- `POST recognition/batch` `{"decisions": [{"id": "<24hex>", "decision": "yes"|"no"}]}`（≤50）→ `{"applied": 12}`。
- `GET recognition/history?limit=50` → `{"items": [{"id", "decision", "decided_at", "preview_url"}]}`。

### “第一次”反馈
- `GET firsts` 每条增加 `"kind"`（类型键）；家长对某类型忽略累计 ≥3 次后，该类型新候选的分数降低（服务端内部），无新字段要求。

## 陪伴（2.27）

### 家人互动（存在布布侧 learning.sqlite，不写回第二大脑）
- `GET online-timeline/{fid}/social` →
```json
{"comments": [{"id": "…", "author": "妈妈", "text": "…", "created_at": "…", "mine": true}],
 "hearts": 3, "hearted": true}
```
- `POST online-timeline/{fid}/comments` `{"text": "1–300 字"}` → 新评论对象。
- `DELETE online-timeline/{fid}/comments/{cid}`（仅本人）→ 204。
- `POST online-timeline/{fid}/heart` `{"on": true}` → `{"hearts": 4, "hearted": true}`。
- `GET social/recent?limit=20` → `{"items": [{"item_id", "author", "text"|null, "kind": "comment"|"heart", "created_at", "preview_url"}]}`。
- `author` 用家庭称呼（PocketBase 成员的 role/称呼），取不到时用“家人”。配置了 ntfy 时，新评论推送给家人（可选）。

### 学习周报
沿用现有 `reviews` / `attempts` / `courses`，App 端汇总，无新接口。
跟读练习沿用现有 attempt：`kind="speak"`（已支持），分数写在 `note`，格式 `score:85`。

## 2.28 课程说明

家长每天可以给一节课写一句“今天学了什么”。课程互动改为由**视频内容（画面描述、歌词/转写、画面文字、采样画面）+ 课程说明**生成，
不再要求音轨里有老师提问。题目和反馈的声音由家里服务器用系统朗读声音合成（不是老师原声），没有可用声音时只显示文字。

### `POST courses`（multipart，增加可选字段）
- 新字段 `note`：字符串，0–2000 字，可省略（默认 `""`）。超长 → 422。其余字段不变。

### `PATCH courses/{cid}` — 修改课程说明并重新生成
- 权限：需要可审核（reviewer）；Cookie 会话需带 `X-Bubu-Learning: 1`（同其他写操作），原生 Bearer 不需要。
- 请求：`Content-Type: application/json`，`{"note": "今天学了秋天的英文儿歌，重点词 leaf, apple, umbrella"}`
  （`note` 必填，字符串，≤2000 字，空字符串表示清空；不接受其他字段 → 422）。
- 服务端去掉首尾空白、合并行内多余空格（保留换行），保存后像 `POST courses/{cid}/retry` 一样重新排队：
  有解析失败的文件先重新解析，否则直接重新生成课程（新版本 draft 取代本课旧版本，已发布的旧版本变为 superseded，互动记录保留）。
- 响应：与 `GET courses/{cid}` 相同的课程详情（含 `note`）。重新生成期间未发布的课程 `state` 为 `processing`（`retry` 同样如此）；
  已发布的课程在新版本生成前保持 `published`。错误：403 无权限 / 404 课程不存在 / 422 内容无效。

### 课程返回增加 `note`
- `GET courses?...` 每项、`GET courses/{cid}`、`POST courses`、`POST courses/{cid}/retry`、`PATCH courses/{cid}` 的课程对象增加
  `"note": "…"`（没有时为 `""`）。

### 课程包（pack.payload）增加字段
```json
{"title": "10.22", "summary": "今天的学习要点……", "intro": "给家长的一两句话：今天学了什么、怎么陪孩子玩",
 "key_words": ["leaf", "apple", "umbrella"],
 "activities": [{"id": "a1", "kind": "listen_choice", "title": "找苹果", "concept": "apple", "instruction": "听一听，苹果在哪里？",
                 "correct_choice": "apple",
                 "prompt": {"role": "cue", "text": "Where is the apple? 苹果在哪里？", "audio_url": "/learning/api/packs/<pid>/resources/<sha>.m4a", "image_url": null},
                 "answer": {"role": "answer", "text": "Yes! Apple! 是苹果！", "audio_url": "…m4a"},
                 "choices": [{"id": "apple", "label": "apple", "image_url": "/learning/api/packs/<pid>/resources/<sha>.jpg"},
                             {"id": "umbrella", "label": "☂️ umbrella", "image_url": null}]}],
 "warnings": []}
```
- 新增 `intro`（≤300 字）、`key_words`（≤12 个）。旧课程包没有时分别为 `""` / `[]`。
- 活动结构、`kind`（listen_choice / color_choice / sort / speak / music）、`role`、选项与 `confirmations` 不变；
  `prompt.source_id/segment_id/start/end` 只在 music 剪取原片歌词时出现，其余题目没有这些字段（App 已按可选处理）。
- `audio_url` 可能为 `null`（服务器没有朗读声音），此时显示 `text`。没有合适画面的选项用 emoji + 文字作为 `label`。
- 题目声音：中文/中英混合用 Tingting（备选 Meijia），纯英文用 Samantha（备选 Karen），单段不超过 12 秒。
- 一节课里上传了内容完全相同的文件时，服务端按内容哈希只存一份素材、只解析一次，`warnings` 会提示“只按一份处理”。

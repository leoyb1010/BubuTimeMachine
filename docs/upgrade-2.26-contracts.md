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

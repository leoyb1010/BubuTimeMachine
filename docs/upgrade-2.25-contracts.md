# 2.25 升级接口契约（并行开发共用）

版本：App 2.25.0 / build 2026102201；服务端 2.25.0。所有接口在 `/learning/api` 下，家庭 Bearer 鉴权（同现有 online-timeline），
JSON 一律 snake_case，iOS 用 `convertFromSnakeCase` 解码。媒体 URL 一律是服务端返回的 `/learning/...` 路径，仍需 Bearer。
第二大脑只读；所有家庭侧决定（确认/忽略/认一认）存在布布学习库（learning.sqlite），不写回第二大脑。
孩子生日：`LEARNING_SUBJECT_BIRTH_DATE=2024-05-22`（早于此日的素材一律不出现）。

## 1. 在线时光（扩展现有）
`GET online-timeline` 现有参数 + `person`（家人名，可选）。
- 每个 item 新增：`aspect`（宽/高，float，未知为 1.0）、`people`（同框家人名数组，不含布布本人）、`place`（地名或 null）、
  `confirmed_by_family`（认一认确认过为 true）。`segments` 只返回通过质量过滤的分段，新增 `transcript_hidden`（被过滤的段数）。
- 有 `query` 时：关键词命中 ∪ 第二大脑网关 bge-m3 语义命中（网关不可用时只用关键词，不报错）；语义结果按相关度在前、其余按时间。
- page=1 时额外返回 `months: [{month:"2026-10", count:int}]`（当前筛选条件下，倒序），供拖动条使用。
`GET online-timeline/people` → `{items:[{name, count}]}`（同框次数倒序）。
`GET online-timeline/items?ids=a,b,c`（≤60 个）→ `{items:[与 feed 同结构]}`，不在专属库内的 id 静默略过。
`GET online-timeline/highlights?date=YYYY-MM-DD` → `{items:[feed item], reason_by_id:{id:"那年今天"|"最近精选"}}`，≤6 个，供小组件/手表。

## 2. 回忆
`GET memories?date=YYYY-MM-DD` → `{items:[{id, kind, title, subtitle, cover_id, cover_url, item_ids:[...], count}]}`
kind ∈ `on_this_day | family | trip | theme`。每条 ≥5 个素材；同一主题/人物有冷却（按日期确定性轮换，同一天结果稳定）；最多 6 条。

## 3. 第一次（家长确认）
`GET firsts?status=candidate|confirmed|all` → `{items:[{id, concept, title, date, item_id, preview_url, description, status}]}`
`POST firsts/{id}/confirm`、`POST firsts/{id}/dismiss`（仅审核家长）→ 返回该条。确认后 App 自行在本机建 Milestone。

## 4. 每月成长小报
`GET monthly` → `{items:[{month:"2026-09", title, summary, highlight_ids:[...], photos, videos, places:[...], firsts:[...], generated_at}]}`（倒序）。
由 worker 每月初生成上月；提供回填命令生成历史月份。

## 5. 声音档案
`GET voices` → `{items:[{id, item_id, captured_at, start, end, text, heard, audio_url}]}`；`heard` 是 Gemini 复听后的文字。
`GET voices/{id}/audio` → audio/mp4 片段。

## 6. 认一认
`GET recognition/candidates?limit=20` → `{items:[{id, preview_url, captured_at, confidence, description}], remaining}`
`GET recognition/{id}/preview` → 缩略图（只允许候选或已决定的 id）。
`POST recognition/{id}` body `{decision:"yes"|"no"}`（仅审核家长）。yes → 进入时光（provenance `family_confirmed`）；no → 从时光排除。
时光详情页“不是布布”也调用 `POST recognition/{id}` `{decision:"no"}`。

## 7. 学习复习（契约不变，算法换 FSRS）
`GET reviews` 结构不变；选题改为 FSRS（两档：答对=Good，答错/求助=Again，目标保持率 0.85，单次 ≤5 题）。

## 8. App 内共享约定
- 手表/小组件“今日精选”：主 App 每次打开时光或回到前台时调用 highlights，把 ≤6 张缩略图（JPEG，最长边 600）与 JSON 写入
  App Group `group.com.bubu.timemachine` 的 `DailyPicks/` 目录：`picks.json` = `[{id, file, captured_at, reason, description}]`。
  小组件读它（无则回退本机照片）；点击深链 `bubu://online/<id>` 打开在线时光详情。
- 深链 `bubu://online/<id>` 与 `bubu://learning` 由 RootTabView 处理（主会话负责）。

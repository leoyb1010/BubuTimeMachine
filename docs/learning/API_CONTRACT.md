# 学习与素材解析 API（2026-10-21）

基线：origin/main d99c63e（2.22.0）。所有新接口均属于现有 Bubu AI 服务的同源 `/learning` 路径。

## 身份

原生首个请求 `GET /learning?date=YYYY-MM-DD&child=<ChildProfile.localId>` 带现有 PocketBase `Authorization: Bearer ...`。服务端验证实际家庭归属，设置只限 `/learning` 的 HttpOnly/SameSite 会话 cookie。Web 后续请求同源；修改请求加 `X-Bubu-Learning: 1`。学校识别专用 token 和维护 API key 不允许获取课程或素材。

课程原声只通过核对后的 source revision + 时间段提供。介绍旁白没有 prompt 角色，不能作为题目播放。课程待确认 → 对照原片核对每道题和答案 → 发布；改题或换片后旧确认失效。

## 原生入口

- `SchoolLearningView(day: Date)` 嵌入同源学习网页，首次携带家庭 Bearer；可选孩子localId。
- 只允许同一 scheme/host/port、`/learning` 下的导航，不把 Bearer 发往任意 URL。
- 学校首页的“今天一起学”进入此页；页面包括上传/待确认、按日期课程、近7天/30天重温。
- 网络失败应有明确重试；不可展示静态假课程冒充已经生成。

## 素材解析

`GET /learning/api/media/{mediaRecordId}/analysis`，Bearer。只处理当前家庭的未删除媒体；首次请求可返回 queued 并排队，后续请求获取结果。

```json
{
  "media_id": "pb-record-id", "content_hash": "sha256", "state": "ready",
  "revision": 1, "provider": "second-brain", "description": "机器识别的描述",
  "ocr": "识别文字", "tags": ["标签"],
  "segments": [{"id":"seg-1","start":13.3,"end":14.1,"text":"Corn."}],
  "warnings": [], "updated_at": "2026-10-21T00:00:00Z"
}
```

state: `queued` / `processing` / `ready` / `failed` / `unavailable`。未就绪时文本为空。字段缺失应兼容；失败不能显示为“无内容”。

`POST /learning/api/media/{mediaRecordId}/analysis/retry` 重试；修改请求需 Bearer 或有效Web会话+自定义头。

Native 本地缓存按服务地址、账号和媒体ID隔离，hash变化丢弃旧解析。不是 SwiftData @Model 变更，不覆盖 Entry.note 或 Media.aiTags。

详情页“素材解析”显示来源、OCR、描述和带时间码的转写，点击时间码使用 `MediaGalleryViewer(..., initialPlaybackSeconds:)` 播放。只在用户已开启对应家庭AI服务时请求；本机未同步媒体提示先同步，离线允许显示匹配的缓存并标记更新时间。

## 分工边界

SwiftData 旧schema、历史原件和发布状态不由本轮学习功能隐式修改。学习来源按“文件”和“授课日期出现记录”分开；同片多日不会被hash去重吞掉。学习状态库、原件和派生产物加入独立备份/导出，不使用第二大脑的个人全库作为家庭数据库。

## Web 学习工作台（同源；主流程为第二大脑自动同步）

- `GET /learning/api/context` → `{user:{id,can_review}, children:[{id,name}], default_child, source_status:{last_sync,imported,pending,error}, school_inbox_display}`。
- `GET /learning/api/days?child_id=&start=&end=` → `{days:[{date,source_count,pack_count,published_count}]}`。
- `GET /learning/api/packs?child_id=&date=` → `{items:[Pack]}`。
- `GET /learning/api/packs/{id}` → `Pack`。Pack为 `{id,child_id,school_date,revision,status,title,payload:{title,summary,activities,warnings},confirmations:[{activity_id,digest}]}`。
- Activity为 `{id,kind,title,concept,instruction,prompt,answer,choices,correct_choice}`；kind为`listen_choice|color_choice|sort|speak|music`。
- prompt/answer为 `{source_id,segment_id,role,text,start,end,audio_url,audio_hash,image_url}`；prompt只播放其自身audio_url，不排队播报instruction或answer；source字段均为服务端确定。
- Choice为 `{id,label,evidence,image_url,color,colors}`；image_url可空；颜色组合使用colors数组，兼容单个color，所有素材URL为同源受保护路径。
- `POST /learning/api/packs/{id}/publish` body `{revision,confirmations:[{activity_id,digest,verified:true}],date_confirmed:true}` → 新Pack。
- `POST /learning/api/packs/{id}/exclude` body `{revision,activity_id}` → 新的待确认Pack，旧确认失效。
- `POST /learning/api/packs/{id}/regenerate` → `{queued:true}`。
- `GET /learning/api/sources?child_id=&date=` → `{items:[{id,name,kind,state,school_date,date_confirmed,analysis:{description,ocr,segments,warnings},original_url}]}`。
- `PATCH /learning/api/sources/{id}/segments` body `{revision,segments:[{id,start,end,text}],school_date,date_confirmed:true}` → 更新来源解析；修改必须核对原片，旧课程确认失效。
- `GET /learning/api/reviews?child_id=&period=week|month&date=` → `{window_start,window_end,items:[{pack_id,activity_id,concept,reason,activity}]}`。activity同上，复习复用已确认原声。
- `POST /learning/api/attempts` body `{id,child_id,pack_id,activity_id,kind,choice?,run_id?,assistance?,note?}` → 记录（选择结果由服务端计算）。重复id幂等，修改同id内容409；不是掌握分数。
- `GET /learning/api/attempts?child_id=` → `{items:[...]}`。
- `POST /learning/api/session` body `{identity,password}`，成功设置HttpOnly cookie；`DELETE` 清会话。
- `POST /learning/api/sync` → `{queued:true}`，请求检查第二大脑新素材；后台仍周期自动同步。

所有修改请求使用 `Content-Type: application/json`（除上传）与`X-Bubu-Learning: 1`；fetch credentials=same-origin。401 显示登录/重新连接，403不重试；409提示重新加载当前版本。

草稿可预览题目/答案用于逐条核对；只有published可进入孩子课程与周月复习。尚无素材的日子显示等待第二大脑，不塞入静态演示题。已有照片时光同步与课堂材料生成分两条准入链；照片无需再手动发时光，老师的教学材料主要来自 iPhone 保存后同步到 iCloud 的内容候选，“布布幼儿园”收件夹作为备用入口。

## 时光解析检索

`GET /learning/api/timeline/search?query=&kind=all|photo|video&start=YYYY-MM-DD&end=YYYY-MM-DD&order=asc|desc&limit=50` →
`{items:[{entry_local_id,media_id,media_local_id,captured_at,description,tags,source:"second-brain",identity_status:"confirmed",match_reason}], total,has_more}`。
只返回当前家庭已通过归属准入并存在于时光事实层的媒体；未确认人物候选不进入此接口。OCR/描述检索均为Gemini派生解释，不修改用户正文。
Native 本机时光仍支持离线基本过滤：图片/视频/全部、拍摄时间范围、最新/最早/最近收录、第二大脑自动/家人记录/全部。有网络且AI已启用时，可额外查询上述解析并映射 entry_local_id 到已同步的本地 Entry；无结果/未同步/失败需分别显示，不假装已有结果。自动来源可按【第二大脑自动整理】标记兼容旧Model，不为本轮过滤修改@Model。

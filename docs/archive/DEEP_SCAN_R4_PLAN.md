# 布布时光机 · 第四轮全盘深扫与升级计划（R4）

> 扫描方式：10 个维度并行深读全部 iOS 代码（154 个 Swift 文件 / 2.7 万行），每个 P1/P2 bug 由 2 名独立"怀疑者"逐行对抗验证（本轮并发误报特别筛过——全局默认 MainActor 下很多"竞态"其实不成立）。
> 结果：**验证成立 P1×8、P2×34**，另有 P3×49、验证中断待核 5 条；升级建议去重后约 40 项，分 4 批。
> 手表按要求不在本轮重点。

---

## 一、必修 Bug（本轮新发现，已对抗验证成立）

### 🔴 P1 —— 会丢数据 / 功能性坏死（8 条，建议本周内全修）

#### 1. 今日照片挂载流：导入失败静默"成功"，且照片被永久标记不再提示
- 位置：`Features/Capture/TodayPhotosSheet.swift:111-129`
- 场景：家人开了 iCloud"优化储存"且弱网时点"收好"→ 每张图 loadImage 返回 nil → 一张没存，却照常播成功触觉、关面板，并把**全部**今日照片写入 handledIDs——这批照片**永远不会再被提示收录**。选 5 成 2 的部分失败同样静默。
- 修法:importSelected 检查 savePickedItems 返回值与成功张数;失败弹提示;只对成功的 asset 调 markHandled。

#### 2. 断网时自然语言记录静默降级 Mock,把捏造的健康数值当真入库
- 位置：`Features/NaturalCapture/NaturalCaptureBar.swift:216-220`
- 场景：AI 服务不可达时 fallback 到 MockAIService——妈妈说"量了身高88体重12公斤"，Mock 固定返回 82cm/10.6kg（confidence 0.88 不触发确认）→ **假数据直接画上成长曲线**。"喝水"永远 120ml、"发烧"永远 37.8℃。
- 修法：真实服务失败就报错或降级成纯文本时光；Mock 仅限 DEBUG/Preview。

#### 3. 详情页编辑后不点"完成"直接返回：改动永不同步，还会被远端覆盖回旧值
- 位置：`Features/Timeline/EntryDetailView.swift:68`
- 场景：编辑态的 TextField/MoodPicker/DatePicker 直接绑定 $entry 即改即生效，但 markEntryDirty 只在"完成"按钮里——左滑返回的改动 syncState 仍是 synced，永不推送；下轮拉取还会被远端**静默覆盖丢失**。
- 修法：绑定 set 时就 markEntryDirty（与 locationBinding 一致），或 onDisappear 且 editing 时补标脏+syncNow。

#### 4. 全屏查看器翻页缓存无上限，连续翻大相册内存线性涨到闪退
- 位置：`DesignSystem/Components/MediaViewer.swift:134`
- 场景：姥姥打开几百张的"全部照片"连续滑：每页持有 2400px 位图（15-25MB）+ 视频页各一个 AVPlayer，cache 只增不减，翻 100 张 1.5GB+ 被系统杀。
- 修法：cache 只留当前页 ±1（或 NSCache 限量），视频页离屏置空 player。

#### 5. Release 构建无处填服务器地址，家人新装机登录必然失败
- 位置：`Features/Settings/AdvancedSettingsView.swift:36` + `ServerConfig.swift:121`
- 场景：地址输入框包在 `#if DEBUG`，Release 显示"服务器：已内置 ✓"，但 defaultBaseURL 实际是**空字符串**且无任何注入路径——TestFlight/正式包新装机永远登录不上。
- 修法：支持 Info.plist 注入 `BUBU_DEFAULT_BASE_URL`（照 defaultAIAPIKey 的做法），或 Release 也放出输入框。

#### 6. 编辑已到期胶囊时解密失败会用空内容覆盖原信——永久丢失
- 位置：`Features/Capsule/CapsuleComposeView.swift:192`
- 场景：钥匙串没同步导致 `try? unseal` 失败 → letter 留空不提示；用户只想换个封面 emoji 点"封存"→ 走重封路径用**空信**重新加密覆盖原 blob。另外重封只回填 letter/voice，photo 字段也会丢。
- 修法：解密失败按锁定分支处理（只许改标题/封面不重封）；重封成功前不覆盖旧 blob 引用。

#### 7. 登录/登出后不重建 API 客户端：新登录不同步、退出后仍在偷偷同步
- 位置：`Features/Settings/AccountView.swift:119`
- 场景 A：新手机首次登录成功，但 apiClient 还是启动时的 Mock → 时光轴一直空白，直到杀 App 重启。场景 B："退出当前账号"只清 config，旧 PocketBaseClient 实例握着凭据继续跑同步。
- 修法：submit 成功后与 logout 后各调一次 `env.reloadServices(context:)`。

#### 8. 删除永远不同步到其他设备，且已删记录会被"复活"
- 位置：`Services/Networking/PocketBaseClient.swift:462`
- 场景：妈妈删掉一张照片（服务器已写 tombstone），爸爸和爷爷的设备**永远看得到**——fetchRecords 把 `isDeleted=true` 直接过滤掉，merge 没有删除路径；更糟 PATCH 强写 `isDeleted=false` 会把 tombstone 翻回来。
- 修法：拉取带上 tombstone，merge 见 isDeleted=true 就删本地并清文件；PATCH 不携带该字段。

### 🟠 P2 —— 明显缺陷（34 条，按域分组）

**记录主流程（Capture）**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 9 | 今日照片收录永久降质：压成 2400px 重编码 JPEG，EXIF/GPS/拍摄时间全丢，happenedAt 记成收录时刻 | TodayPhotosSheet.swift:117 | 改 requestImageDataAndOrientation 拿原始 Data 走 mediaStore.savePhoto，回填 asset.creationDate/location |
| 10 | 快速记录部分媒体失败静默丢照片（有文字兜底时 9 张 iCloud 图无声消失） | CaptureModel.swift:148 | 比对期望张数 vs savedCount，不符明示"N 张没导入"并保留重试 |
| 11 | updatePreviews 并发竞态：加载间隙点 X 会**删错媒体**（删掉刚拍的相机照） | CaptureModel.swift:197 | 单飞可取消任务；删除改按稳定 ID 不按位置索引 |
| 12 | 选中媒体全尺寸 UIImage 常驻内存，多选大图 OOM | CaptureModel.swift:216 | 预览降采样 ~300px；导入改逐张流水线 |
| 13 | CaptureModel 缓存创建时的 role，切身份后新记录**署名错人** | CaptureModel.swift:46 | 保存时实时读 env.config.currentRole |

**健康与自然语言**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 14 | 数字框每敲一键就钳制：体温/身高/头围键盘输入必得错值（输 37.8 输到 3 就被夹成 35） | HealthRecordSheet.swift:639,691 | 输入用本地字符串缓存，失焦再 parse+clamp |
| 15 | 编辑任何健康记录丢 amountText（"半碗"、体检摘要被清空） | HealthRecordSheet.swift:124,202 | draft 保留原值，仅新数据才覆盖 |
| 16 | 编辑体检记录不更新 GrowthMeasurement，曲线与记录脱节 | HealthRecordSheet.swift:85 | 编辑路径同月查找 checkup 来源的测量并更新 |
| 17 | 百分位不插值：24-60 月龄解读误差大且与图表矛盾 | WHOGrowthStandard.swift:62 | 相邻 Band 线性插值（与图表渲染一致） |
| 18 | 确认页"体检护理"卡可编辑身高体重，落库整体丢弃 | NaturalCaptureReviewSheet.swift:288 | .checkup 分支复用 saveGrowth 落 GrowthMeasurement |
| 19 | 疫苗模糊匹配把重复口述自动打到**下一剂** | NaturalCaptureRouter.swift:116 | 同名同日去重；确认页明示"将打卡：乙肝·第2剂" |
| 20 | 深色下数字输入框白底米字不可读 | HealthRecordSheet.swift:627 | 换 BubuTheme.Color.card/softFill |

**时光轴 / 相册 / 动态**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 21 | 相册详情分批加载**卡死在 180 张**，更早的永远出不来 | AlbumDetailView.swift:37 | 哨兵放进 LazyVGrid 或倒数第 N 个 onAppear 追加 |
| 22 | 动态墙看不到其他家人的评论/语音/里程碑（FeedEvent 不同步） | FamilyFeedView.swift:7 | 从已同步的 Comment/Milestone 现场派生事件 |
| 23 | 动态墙按 kind+目标去重，同一记录多条评论互吞 | FamilyFeedView.swift:29 | 去重仅限 entryCreated，其余按 event.id |

**魔法屋 AI**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 24 | 打字机动效不可取消：切换记录时上一条残尾拼到新文本头上 | FirstPersonDiaryView.swift:227（FamilyEnsembleView 同） | 可取消 Task，切换先 cancel |
| 25 | 成片轮询脆弱：一次网络抖动/超 3 分钟丢 jobId，重试重复渲染 | GrowthMovieView.swift:276 | 轮询重试 2-3 次；jobId 持久化续接 |
| 26 | 高清成片看完即丢，再看要整部重渲 | GrowthMovieView.swift:240 | 成片移入 Documents + "播放高清版"按钮 |
| 27 | 问答"去年今天在干嘛"必答非所问（检索无日期感知） | BubuQAView.swift:156 | 日期意图解析转窗口查询；里程碑/健康纳入检索 |
| 28 | 家人合奏配了真 AI 仍输出写死模板，且硬编码"布布" | FamilyEnsembleView.swift:123 | 接 ensemble 端点，降级明示"离线简易版" |

**设置 / 身份 / 胶囊 / 相框**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 29 | 第二台设备走完引导必产生**重复"布布"档案**污染全家 | OnboardingView.swift:183 | 引导加"加入已有家庭"分支；档案按单例合并 |
| 30 | 恢复码"恢复"无校验，可静默覆盖全家正确密钥 | CapsuleRecoveryView.swift:134 | 先用现有 v3 胶囊试解验证，失败拒写 |
| 31 | 深色下胶囊信纸/24 词恢复码白纸白字 | CapsuleUnlockView.swift:185 | 固定纸底配固定深字 |
| 32 | 年册 PDF 主线程同步生成，整机卡死数秒-数十秒 | YearbookView.swift:164（YearbookExporter.swift:34 同） | 移 Task.detached + 页码进度 |
| 33 | 相框模式播放列表只建一次：跨天"那年今日"过期、新照片永不出现 | PhotoFrameView.swift:46 | 按日期/entries.count 用 .task(id:) 重建 |

**同步 / 网络 / 系统**
| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 34 | 多设备并发编辑后推者胜，旧覆盖新无提示 | SyncEngine.swift:256 | push 前比对远端 editedAt，新则先合并 |
| 35 | 同步逐条 reloadAllTimelines：烧光 WidgetKit 当日预算 + 首次全量同步卡顿 | SyncEngine.swift:952 | 整轮末尾只刷一次 |
| 36 | 网络客户端整体 MainActor：传大视频主线程拼 multipart，App 冻结数秒 | PocketBaseClient.swift:646 | 客户端 nonisolated（已 Sendable 不碰 UI） |
| 37 | 录音无 AVAudioSession 中断处理，来电丢后半段语音 | AudioRecorder.swift:32 | 监听 interruptionNotification 自动收尾保留已录 |
| 38 | 控制中心/Action Button"记录布布"完整模式不拉起面板，残留标志之后误弹 | RootTabView.swift:75 | 加 onChange(pendingQuickCapture) 消费（与 SimpleMode 对齐） |
| 39 | 生日**当天**倒计时显示"还有365天"，小组件"生日快乐🎂"永不可达 | AgeCalculator.swift:55 | 当天 month/day 相等先返回 0 |
| 40-42 | （同 #4/#12/#32 的重复报告，合并处理） | — | — |

### ⚪ 验证中断待核（限额中断未走完对抗验证，修前先人工确认）
- **星夜主题在浅色系统下全 App 文字不可读**（ThemedBackground.swift:24）——夜间主题体系断裂，疑似 P1
- 下载成片整段 mp4 读进内存，长片内存告警（BubuAIService.swift:73）→ 改 URLSession.download(for:)
- 同步每合并一条就全量重建 Widget 快照，首次同步 O(N²)（SharedDefaults.swift:120）
- 头像从不生成缩略图 + widget 2MB 上限：桌面小组件头像永远是"布"字兜底（ChildProfileView.swift:194）
- 缩略图在同步下载完成后不刷新，一直占位图（MediaThumbnail.swift:43）

---

## 二、升级机会（去重合并后分 4 批，按家庭价值排序）

### 批次 E · 零操作与省力记录 ⭐️ 最高优先
| 项 | 为什么值得 | 量 |
|---|---|---|
| E-1 语音自动转写落库+全文可搜 | iOS 26 端侧 SpeechAnalyzer（离线、免费、快），服务器 Whisper 兜底。三年语音变成可搜索文字，还能喂给问答 RAG——"布布第一次叫妈妈"直接搜到那段录音 | M |
| E-2 交互式健康打卡小组件 + App Intents | 桌面/锁屏一键"喂奶/睡觉/喝水/换尿布"**不开 App**；Siri"记录布布喝奶"。半夜喂奶单手锁屏就能打卡，这是喂养期最高频操作 | M |
| E-3 哄睡 Live Activity | 开始/结束一键，锁屏和灵动岛实时计时。睡眠是唯一有"进行中"状态的记录，天然适合 Live Activity（BubuActivityAttributes 已建好，全仓库零调用——接上就行） | M |
| E-4 疫苗到期本地通知 + 打卡自动排下一针 | 数据和排期逻辑都有了，就差 UNCalendarNotificationTrigger。错过疫苗是真实损失 | S |
| E-5 "那年今日"通知带当年照片附件 + 预排 30 天 | UNNotificationAttachment 挂缩略图，通知本身就是回忆。现通知是纯文字 | S |
| E-6 今日挂载流支持视频 + Vision 连拍去重 | 现在只挂照片；连拍 20 张挑最清晰一张再提示 | M |
| E-7 iOS 26 Foundation Models 端上解析兜底 | 自然语言记录离线也能走端侧模型解析（顺带根治 P1-2 的 Mock 假数据问题） | L |

### 批次 F · 家庭连接与回忆
| 项 | 为什么值得 | 量 |
|---|---|---|
| F-1 "那年今日"照片轮播小组件 | 桌面小组件变成自动翻页的成长相框（TimelineProvider 多 entry 免刷新预算），全家每天解锁手机就是布布 | M |
| F-2 里程碑关联照片/时光 | 点亮里程碑时挂上那一刻的照片，星盘点星回到现场——里程碑从"清单"变"回忆" | M |
| F-3 家庭动态墙产品化 | 派生家人评论/语音/里程碑事件 + 未读红点（顺带修 P2-22/23），老人打开就看到"妈妈昨天给布布记了什么" | M |
| F-4 照片保存到系统相册 + 分享 | 查看器/相册多选导出——现在照片进得来出不去，发家族群要截图 | M |
| F-5 PocketBase SSE 实时同步 | 替代 30 秒轮询，爸爸发的照片妈妈手机秒到；PocketBase 原生支持 realtime 订阅 | M |
| F-6 今日一问"全家合唱" | 同一天各家人的答案聚在一起看 | M |
| F-7 署名精确到"成员"而非"称谓" | 两位姥姥/换手机场景下署名不再混淆（FamilyMember 已有模型，Entry 存 memberId） | M |

### 批次 G · 档案级可靠性底座
| 项 | 为什么值得 | 量 |
|---|---|---|
| G-1 相册收录保真管线 | 原始 Data + EXIF/GPS + 逐张流式导入（= 修 P2-9/12 的正解，30 年档案不能存压缩图） | M |
| G-2 后台续传：background URLSession + BGAppRefresh | 现在传一半锁屏就断；家庭相册 App 的上传必须后台完成 | L |
| G-3 SwiftData 版本化 Schema + 容器失败恢复 | 现在 modelContainer 失败直接 fatalError——版本升级万一迁移失败会**锁死全家数据**。要 VersionedSchema + 恢复模式 | M |
| G-4 新设备"接布布回家"首装流程 | 并行批量下载 + 大进度条（顺带修 P1-7 / P2-29 的新机场景） | M |
| G-5 时间胶囊媒体加密闭环 | 封存删明文、解封走 tmp——现在信加密了但附带照片是明文 | M |
| G-6 定期备份提醒 + BGProcessingTask 后台预打包 | 自托管家庭的最后保险 | M |

### 批次 H · 体验打磨与适老
| 项 | 为什么值得 | 量 |
|---|---|---|
| H-1 夜间体验重塑 | 星夜主题强制深色（修待核 P1）+ 深色下 6 主题保留辨识度——目前深色下主题差异基本消失 | M |
| H-2 适老 Dynamic Type 全覆盖 | 设计系统大量固定字号，老人系统调大字号 App 不跟——对四位老人是刚需不是锦上添花 | M |
| H-3 TipKit 渐进引导 | "收进绘本""长按换主题""身份切换"这些好功能藏得深，老人发现不了（5 个维度不约而同提了这条） | S |
| H-4 把 4 张已画好的空状态插画接上 | BubuEmptyAlbum/BubuEmptyTimeline 等资产已入库，代码零引用 | S |
| H-5 问答体验完善 | 日期意图检索（修 P2-27）+ 出处点击跳转原记录 + 会话持久化 + 流式回答 | M |
| H-6 成片库 + 渲染进度 Live Activity | 高清电影可存可重看（修 P2-25/26）+ 锁屏看合成进度 | M |
| H-7 绘本"讲故事模式" + 导出 PDF | AVSpeechSynthesizer 朗读自动翻页（老人给娃讲故事）；PDF 打印成实体书 | M |
| H-8 CoreSpotlight 索引 | iPhone 系统搜索直达"第一次走路"那条记录（3 个维度都提了） | M |
| H-9 成长曲线交互 | chartXSelection 点选查看 + 月龄插值（配合修 P2-17） | S |
| H-10 CoreHaptics 仪式触感 | "封存/破封/点亮"渐强触觉编排，家庭仪式感 | S |
| H-11 VoiceOver 语义补全 | 自绘组件可发现、可操作 | S |
| H-12 NWPathMonitor 网络感知 | 断网静默、恢复秒传、仅 Wi-Fi 传大视频开关 | S |
| H-13 WeatherKit 真实天气 | 替换首页装饰性"假天气"，顺手写进每条记录的当天天气 | M |
| H-14 Liquid Glass 纵深 | iOS 26 玻璃形变衔接底栏"+"与记录面板 | M |

---

## 三、建议节奏

| 顺序 | 内容 | 出口标准 |
|---|---|---|
| ① 急修周 | P1×8 + 待核 5 条中确认的 + P2 里的数据类（9/13/14/15/18/19/29/30/34） | 全部有回归验证；多设备同步删除/编辑实测 |
| ② 批次 E | E-1~E-5（省力三件套先行） | 真机锁屏打卡/转写实测 |
| ③ 批次 G | G-1/G-3 先做（保真+Schema 是底座），G-2 随后 | 大视频后台传完实测 |
| ④ 批次 F | F-1/F-2/F-5 | 双机实时性实测 |
| ⑤ 批次 H | H-1~H-5 优先 | 深色/大字号全页面过检 |

其余 P2/P3 随批顺带修（P3 清单见附录）。每批照例：clean build + 全部测试绿 → 真机核验 → 中文 commit → push。

---

## 附录 · P3 清单（49 条，随批顺带修）
| # | 问题 | 位置 |
|---|---|---|
| 1 | context.save() 失败后脏 Entry 残留，重试保存产生重复条目 | `Features/Capture/CaptureModel.swift:170-173` |
| 2 | 首页"那年今日"卡年份文案按时分算年差：晚间拍的两年前照片显示"1年前的今天" | `Features/Capture/CaptureHomeView.swift:977-980` |
| 3 | 相册视频被拷贝两次进 tmp 且从不清理：记一段 4K 视频临时盘占飙数百 MB | `Features/Capture/CaptureModel.swift:211,293` |
| 4 | 取消记录/删除录音时语音 m4a 成为孤儿文件永久滞留媒体目录 | `Features/Capture/QuickCaptureSheet.swift:472-479` |
| 5 | AI 悬浮球可被拖出屏幕外且无法找回 | `Features/Capture/CaptureHomeView.swift:1087-1090` |
| 6 | 首页 body 每次同步进度刷新都全量遍历 entries×media，大库时同步期间首页卡顿 | `Features/Capture/CaptureHomeView.swift:902-906` |
| 7 | 编辑喝水记录时「今日已记录」把本条水量算了两遍 | `Features/Health/HealthRecordSheet.swift:21-26, 368` |
| 8 | 睡眠「醒来」时间显示默认值但不落库，只调入睡时间保存后没有时长 | `Features/Health/HealthRecordSheet.swift:405-417` |
| 9 | 多设备对同一剂次各自打卡后，重复记录不可见、无法删除，取消打卡会「复活」 | `Features/Health/VaccineView.swift:20-24` |
| 10 | 时光轴列表删除记录：小组件不刷新、同步不立即触发 | `Features/Timeline/TimelineView.swift:291` |
| 11 | 改日期后时光轴月份分组不重建，记录挂在旧月份分组下 | `Features/Timeline/TimelineView.swift:40` |
| 12 | 时光轴封面图不保序 + hashValue 取色导致每次启动颜色/封面随机变化 | `Features/Timeline/TimelineView.swift:144` |
| 13 | 详情页追加照片在主线程全尺寸解码+缩图，UI 冻结数秒 | `Features/Timeline/EntryDetailView.swift:486` |
| 14 | Ken Burns 缩放平移从未生效：电影播放实际是静态图硬切+淡入 | `Features/AIStudio/GrowthMoviePlayer.swift:70-82, 250-259` |
| 15 | AI 没引用时伪造「出处」：把未被引用的检索结果当引用展示 | `Features/AIStudio/BubuQAView.swift:136-139` |
| 16 | aiNarration 状态陈旧：换筛选重新生成时可能把上一部电影的旁白带进新片 | `Features/AIStudio/GrowthMovieView.swift:20, 356-368, 280` |
| 17 | 「year」参数语义混用：有筛选时传年龄(0/1/2)，无筛选时传公历年(2026) | `Features/AIStudio/GrowthMovieView.swift:277, 358-359` |
| 18 | 绘本阅读器进度点不滚动：章节多时挤爆顶栏 | `Features/Story/BubuStoryReaderView.swift:57-64` |
| 19 | 绘本封面缓存键用 entryId 且把缩略图文件名当原图路径传 | `Features/Story/BubuStoryReaderView.swift:178-187（配合 StoryChapter.swift:66-70）` |
| 20 | 问问布布/成长报告不跟随主题背景，报告页还裸写 .orange/.purple | `Features/AIStudio/BubuQAView.swift:37；GrowthReportView.swift:29, 61-63` |
| 21 | 长辈自己手机上『切换到完整版』会静默变成『妈妈』身份，后续记录署名错乱 | `Services/Networking/ServerConfig.swift:22` |
| 22 | 相框控制条自动隐藏计时器叠加，操作中途控制条突然消失 | `Features/PhotoFrame/PhotoFrameView.swift:196` |
| 23 | 编辑未到期胶囊时快捷日期 chips 未禁用，看起来改了解锁日实际没改 | `Features/Capsule/CapsuleComposeView.swift:135` |
| 24 | 胶囊语音原文件明文留在媒体目录，『封存后谁也打不开』对语音不成立 | `Services/Security/CapsuleVault.swift:51` |
| 25 | 一条被服务器拒绝的『毒丸』记录会永久卡死所在集合的增量游标，每 30 秒全量重拉 + 永久显示『还在等网络』 | `Services/Sync/SyncEngine.swift:795` |
| 26 | 增量游标存 UserDefaults 且不随服务器/账号切换重置：换服务器或从备份恢复后历史数据永远拉不全 | `Services/Sync/SyncEngine.swift:51` |
| 27 | 403 被当作 token 过期处理：服务器规则错误时每个待推项每轮触发一次密码重登录，可能撞上 PocketBase 认证限流 | `Services/Networking/PocketBaseClient.swift:1125` |
| 28 | 锁屏『回一句』写进另一个 ModelContainer，前台时光轴不刷新且失败被吞 | `Services/NotificationReplyHandler.swift:48` |
| 29 | 时间胶囊语音明文残留：封存后源 m4a 永不删除 | `Services/Security/CapsuleVault.swift:51` |
| 30 | 异地设备每次开启胶囊都新写一个孤儿语音 blob | `Services/Security/CapsuleVault.swift:83` |
| 31 | 相册扫描 handledIDs 在 UserDefaults 中无限增长 | `Services/Media/PhotoLibraryScanner.swift:16` |
| 32 | 语音转写请求用默认 60s 空闲超时，长语音必失败 | `Services/AI/BubuAIService.swift:114` |
| 33 | 缩略图后台补齐无去重，同图多档位并发生成孤儿缩略图 | `Services/Media/ThumbnailProvider.swift:84` |
| 34 | 『今天拍的』收录丢失 EXIF 拍摄时间与 GPS | `Features/Capture/TodayPhotosSheet.swift:118` |
| 35 | 手表语音导入失败即静默丢弃，无任何补救 | `Services/WatchConnectivityManager.swift:75` |
| 36 | 档案导出 data.json 遇制表符/回车生成非法 JSON | `Services/Media/ArchiveExporter.swift:222` |
| 37 | 全新安装的用户完成首启引导后立刻被弹「更新好啦 v1.3.0」升级弹窗 | `App/BubuTimeMachineApp.swift:259` |
| 38 | Siri「记一笔」落库后桌面小组件不更新；App 进程存活时主界面时光轴也看不到这条记录 | `App/BubuAppIntents.swift:27-39` |
| 39 | 每次冷启动都在首帧前做全量存储体检：打开 3 个 SQLite 库 + 逐文件遍历新旧媒体目录，耗时随照片数永久增长 | `App/StorageMigrator.swift:64-94` |
| 40 | 「生日月」App 图标永远不会生效；晚霞主题无图标映射 | `DesignSystem/AppIconManager.swift:26` |
| 41 | BubuTheme.Color.hue() 把 HSL 设计稿误移植成 HSB，产出霓虹色而非马卡龙粉彩，并造成白字对比失败 | `DesignSystem/BubuTheme.swift:102` |
| 42 | 硬编码白色叠层 × 动态文字色：深色模式下多处文字对比崩坏 | `Features/Milestones/MilestoneSheets.swift:126` |
| 43 | 录音途中滑掉面板会静默丢弃整段录音 | `DesignSystem/Components/VoiceComponents.swift:67` |
| 44 | 多条语音可同时播放（每个气泡各自持有 AudioPlayer） | `DesignSystem/Components/VoiceComponents.swift:132` |
| 45 | 语音播放把音频会话锁死为 .playback，之后音效不再跟随静音键、家人音乐被打断后不恢复 | `DesignSystem/BubuSound.swift:47` |
| 46 | Siri/快捷指令「记一笔」落库后不刷新小组件快照，桌面「今日时光」保持旧内容 | `App/BubuAppIntents.swift:28` |
| 47 | iOS 18+/26 主屏「染色」模式下，头像照片被渲染成实心色块圆片 | `BubuWidgets/BubuWidgets.swift:75` |
| 48 | 录音 Live Activity 锁屏视图硬编码白字，浅色锁屏下对比度不足 | `BubuWidgets/BubuLiveActivity.swift:51` |
| 49 | 小组件「本月照片」只统计最近 40 条记录，多人家庭必然偏小 | `App/SharedDefaults.swift:148` |

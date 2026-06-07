/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · PocketBase 集合定义（一次性创建全部 collection）
// 部署：把本文件放到 pocketbase 可执行文件同级的 pb_migrations/ 目录，启动时自动应用。
//
// 设计原则：
//  - 每个集合都有 localId（客户端 UUID），用于幂等去重——同一条记录多设备/重试不重复。
//  - 规则权限：家庭三人共享，登录用户可读写全部（家庭内无隐私墙；隐私靠 Tailscale 内网 + 账户）。
//  - 媒体走 PocketBase 内置 file 字段，自动存储 + 生成 URL。

migrate((app) => {
  const authRule = '@request.auth.id != ""'  // 仅登录用户可访问

  // 通用：给集合加 localId + 时间戳的辅助
  function baseFields(extra) {
    return [
      { name: 'localId', type: 'text', required: true, presentable: true,
        unique: true },
      ...extra,
    ]
  }

  // ---- entries（记录：聚合根）----
  const entries = new Collection({
    type: 'base', name: 'entries',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'title', type: 'text' },
      { name: 'note', type: 'text' },
      { name: 'firstPersonNote', type: 'text' },
      { name: 'happenedAt', type: 'date', required: true },
      { name: 'locationName', type: 'text' },
      { name: 'latitude', type: 'number' },
      { name: 'longitude', type: 'number' },
      { name: 'authorRole', type: 'text', required: true },
      { name: 'mood', type: 'text' },
      { name: 'isArchived', type: 'bool' },
      { name: 'editedAt', type: 'date' },
      { name: 'happenedAtClient', type: 'date' },
    ]),
  })
  app.save(entries)

  // ---- media（照片/视频/音频）----
  const media = new Collection({
    type: 'base', name: 'media',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'entryLocalId', type: 'text', required: true },
      { name: 'mediaType', type: 'text', required: true },  // photo/video/audio
      { name: 'file', type: 'file', maxSelect: 1, maxSize: 524288000 }, // 500MB
      { name: 'thumbnail', type: 'file', maxSelect: 1, maxSize: 10485760 },
      { name: 'durationSeconds', type: 'number' },
      { name: 'width', type: 'number' },
      { name: 'height', type: 'number' },
      { name: 'aiTags', type: 'json' },
    ]),
  })
  app.save(media)

  // ---- comments（家人合奏）----
  const comments = new Collection({
    type: 'base', name: 'comments',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'entryLocalId', type: 'text', required: true },
      { name: 'authorRole', type: 'text', required: true },
      { name: 'text', type: 'text' },
      { name: 'voiceFile', type: 'file', maxSelect: 1, maxSize: 52428800 },
      { name: 'voiceDuration', type: 'number' },
      { name: 'voiceWaveform', type: 'json' },
    ]),
  })
  app.save(comments)

  // ---- voicenotes（记录上的语音）----
  const voicenotes = new Collection({
    type: 'base', name: 'voicenotes',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'entryLocalId', type: 'text', required: true },
      { name: 'authorRole', type: 'text', required: true },
      { name: 'file', type: 'file', maxSelect: 1, maxSize: 52428800 },
      { name: 'durationSeconds', type: 'number' },
      { name: 'transcript', type: 'text' },
      { name: 'waveform', type: 'json' },
    ]),
  })
  app.save(voicenotes)

  // ---- milestones（里程碑）----
  const milestones = new Collection({
    type: 'base', name: 'milestones',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'title', type: 'text', required: true },
      { name: 'category', type: 'text' },
      { name: 'emoji', type: 'text' },
      { name: 'detail', type: 'text' },
      { name: 'happenedAt', type: 'date' },
      { name: 'ageDescription', type: 'text' },
      { name: 'isCustom', type: 'bool' },
    ]),
  })
  app.save(milestones)

  // ---- firsttimes（人生第一次）----
  const firsttimes = new Collection({
    type: 'base', name: 'firsttimes',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'what', type: 'text', required: true },
      { name: 'happenedAt', type: 'date' },
      { name: 'detectedByAI', type: 'bool' },
      { name: 'confirmedByParent', type: 'bool' },
      { name: 'entryLocalId', type: 'text' },
    ]),
  })
  app.save(firsttimes)

  // ---- voicememos（成长之声）----
  const voicememos = new Collection({
    type: 'base', name: 'voicememos',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'kind', type: 'text', required: true },  // childVoice/familyVoice
      { name: 'file', type: 'file', maxSelect: 1, maxSize: 104857600 },
      { name: 'transcript', type: 'text' },
      { name: 'ageYears', type: 'number' },
      { name: 'recordedAt', type: 'date' },
      { name: 'durationSeconds', type: 'number' },
      { name: 'title', type: 'text' },
      { name: 'waveform', type: 'json' },
    ]),
  })
  app.save(voicememos)

  // ---- members（家庭成员）----
  const members = new Collection({
    type: 'base', name: 'members',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'name', type: 'text', required: true },
      { name: 'relation', type: 'text' },
      { name: 'avatarEmoji', type: 'text' },
      { name: 'themeColorHex', type: 'text' },
      { name: 'isPrimary', type: 'bool' },
    ]),
  })
  app.save(members)

  // ---- childprofile（布布档案，全家共一份）----
  const childprofile = new Collection({
    type: 'base', name: 'childprofile',
    listRule: authRule, viewRule: authRule, createRule: authRule,
    updateRule: authRule, deleteRule: authRule,
    fields: baseFields([
      { name: 'name', type: 'text', required: true },
      { name: 'birthday', type: 'date', required: true },
      { name: 'gender', type: 'text' },
      { name: 'birthPlace', type: 'text' },
      { name: 'avatar', type: 'file', maxSelect: 1, maxSize: 10485760 },
      { name: 'heroBackground', type: 'file', maxSelect: 1, maxSize: 20971520 },
    ]),
  })
  app.save(childprofile)

}, (app) => {
  // 回滚：删除全部集合
  const names = ['media','comments','voicenotes','firsttimes','voicememos',
                 'milestones','members','childprofile','entries']
  for (const n of names) {
    try { app.delete(app.findCollectionByNameOrId(n)) } catch (e) {}
  }
})

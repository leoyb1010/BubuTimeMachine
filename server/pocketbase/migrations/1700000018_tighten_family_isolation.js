/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 收紧家庭隔离（把 0009 承诺的「后续收紧」真正做掉）
//
// 0009 当时写的是：
//   familyRule = '@request.auth.id != "" && (@request.auth.familyId = "" || familyId = "" || familyId = @request.auth.familyId)'
//   users.updateRule = 'id = @request.auth.id'
// 两个 OR 分支都是放行，而 users 的更新规则是**记录级**的、不限制字段，
// familyId 只是普通 TextField。于是任何已登录用户
//   PATCH /api/collections/users/records/<自己的 id>  body {"familyId": ""}
// 就能对全部 14 张业务表拿到全库读写。
//
// 0009 的文件头把这写成了刻意的升级兼容（「老数据 familyId 为空仍可被已登录用户读取，
// 避免升级后把历史记录锁死」「后续可在数据回填完成后进一步收紧规则」），
// 在「单家庭 + 内网 + 已关公开注册」的部署下今天确实不可被外人利用。
// 但那句「后续收紧」从写下那天起就没做过，而幼儿园相关功能会让更多家人账号进来。
//
// 这条迁移做三件事，且**先回填再收紧**，不会把历史记录锁死：
//   1. 把所有 familyId 为空的业务记录回填成唯一那个家庭的 id（只在确实唯一时才动）。
//   2. 把 users.updateRule 收成带字段守卫，用户改不动自己的 familyId。
//   3. 只有在确认没有残留空 familyId 之后，才删掉规则里的放行分支；
//      否则保持原规则并打日志说明——宁可不收紧，也不能让谁的记录突然消失。

migrate((app) => {
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]

  // ---- 1. 先把 users.familyId 锁住，防止收紧过程中有人自助改空 ----
  const users = safeFind(app, 'users')
  if (users) {
    // 记录级规则之外再加字段守卫：请求体要么不带 familyId，要么必须与当前值一致。
    users.updateRule = 'id = @request.auth.id && (@request.body.familyId:isset = false || @request.body.familyId = familyId)'
    app.save(users)
    console.log('[0018] users.updateRule 已加 familyId 字段守卫')
  }

  // ---- 2. 回填历史空 familyId ----
  const familyId = soleFamilyId(app)
  if (!familyId) {
    console.log('[0018] 家庭数不唯一或为 0，跳过回填与规则收紧（保持 0009 的兼容规则）')
    return
  }

  let remaining = 0
  for (const name of business) {
    if (!safeFind(app, name)) { continue }
    exec(app, `UPDATE {{${name}}} SET [[familyId]] = '${familyId}'
               WHERE [[familyId]] IS NULL OR [[familyId]] = ''`)
    remaining += countEmpty(app, name)
  }
  exec(app, `UPDATE {{users}} SET [[familyId]] = '${familyId}'
             WHERE [[familyId]] IS NULL OR [[familyId]] = ''`)

  if (remaining > 0) {
    console.log(`[0018] 仍有 ${remaining} 条记录 familyId 为空，本次不收紧规则`)
    return
  }

  // ---- 3. 回填干净了，才真正删掉放行分支 ----
  const strictRule = '@request.auth.id != "" && @request.auth.familyId != "" && familyId = @request.auth.familyId'
  const strictCreate = '@request.auth.id != "" && @request.auth.familyId != "" && @request.body.familyId = @request.auth.familyId'

  for (const name of business) {
    const collection = safeFind(app, name)
    if (!collection) { continue }
    collection.listRule = strictRule
    collection.viewRule = strictRule
    collection.updateRule = strictRule
    collection.createRule = strictCreate
    collection.deleteRule = null      // 删除仍然只留给超管，客户端走 tombstone
    app.save(collection)
  }

  const families = safeFind(app, 'families')
  if (families) {
    families.listRule = '@request.auth.id != "" && id = @request.auth.familyId'
    families.viewRule = '@request.auth.id != "" && id = @request.auth.familyId'
    app.save(families)
  }
  console.log('[0018] 家庭隔离规则已收紧：不再接受空 familyId')

  function soleFamilyId(app) {
    try {
      const rows = app.findRecordsByFilter('families', '', '', 2, 0)
      return rows && rows.length === 1 ? rows[0].id : null
    } catch (_) { return null }
  }

  function countEmpty(app, table) {
    try {
      const rows = app.db()
        .newQuery(`SELECT count(*) AS n FROM {{${table}}}
                   WHERE [[familyId]] IS NULL OR [[familyId]] = ''`)
        .all()
      return rows && rows.length ? Number(rows[0].n || 0) : 0
    } catch (_) { return 0 }
  }

  function exec(app, sql) {
    try { app.db().newQuery(sql).execute() } catch (err) { console.log(`[0018] ${err}`) }
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (_) { return null }
  }
}, (app) => {
  // 回滚只放开规则，**不回退回填**：把 familyId 清空等于重新制造「全局可读」的记录。
  const familyRule = '@request.auth.id != "" && (@request.auth.familyId = "" || familyId = "" || familyId = @request.auth.familyId)'
  const familyCreateRule = '@request.auth.id != "" && (@request.auth.familyId = "" || @request.body.familyId = "" || @request.body.familyId = @request.auth.familyId)'
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]
  for (const name of business) {
    let collection = null
    try { collection = app.findCollectionByNameOrId(name) } catch (_) { continue }
    collection.listRule = familyRule
    collection.viewRule = familyRule
    collection.updateRule = familyRule
    collection.createRule = familyCreateRule
    app.save(collection)
  }
  try {
    const users = app.findCollectionByNameOrId('users')
    users.updateRule = 'id = @request.auth.id'
    app.save(users)
  } catch (_) {}
})

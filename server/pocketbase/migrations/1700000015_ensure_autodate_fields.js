/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 全集合 created/updated autodate 兜底（幂等）
//
// 背景（2026-07-23 事故 + 2026-09-04 审计）：
// PocketBase v0.23+ 不再自动创建 created/updated 系统字段，必须显式声明为 autodate。
// 0000 号的 baseFields() 没加，于是 iOS 端 PocketBaseClient.listRecordsQueryItems() 的
// 增量拉取（sort=updated 与 filter=(updated>'…')）对**每一个集合的每一次拉取**都返回
// 400 invalid sort field "updated" —— 云端同步从未成功过一次。
//
// 当时的修复是在生产 mini 上手写了 1700000011_add_autodate_fields.js，但那份文件落在
// pb_migrations/ 运行时目录里，而 server/.gitignore 恰好排除了它 —— **修复从未进仓库**。
// 后果：换机器、重装、或跑 ops/restore-drill.sh 恢复演练后，start_pocketbase.sh 用的是
// 受 git 管理的 --migrationsDir，事故原样复现。而且 0012 之后新建的四个集合
// （automation_jobs / derived_artifacts / families / users）即便在 mini 上也从未有过 autodate。
//
// 这条迁移的定位：**不是补写那份历史文件，而是一条与它无关、可反复安全执行的兜底**。
// - 号段用 0015，绝不与 mini 上已应用的 0011 冲突。
// - 逐集合检查，字段已存在就跳过 —— 所以在 mini 上运行时，前 15 个集合原样不动，
//   只给后四个补齐；在全新机器上运行时，19 个集合一次性补全。
// - 补完必须回填历史行：新加的 autodate 列对既有行是空值，而空值不满足
//   filter=(updated>'…')，那些记录会对所有设备永久不可见。回填优先用 clientUpdatedAt
//   （全表都有、且正是客户端的版本号），没有就落到一个足够早的固定时间，
//   保证首次同步能把它们全部拉回来。

migrate((app) => {
  // 0009 定义的业务集合 + 0012/0013 之后新增的集合 + auth 集合。
  const collections = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
    'automation_jobs', 'derived_artifacts', 'families', 'users',
  ]

  // 早于任何真实记录的固定时间：既有行没有 clientUpdatedAt 时用它兜底，
  // 保证这些行落在所有增量游标之前，首次同步一定会被拉到。
  const EPOCH = '2000-01-01 00:00:00.000Z'

  for (const name of collections) {
    const collection = safeFind(app, name)
    if (!collection) {
      console.log(`[0015] 跳过不存在的集合：${name}`)
      continue
    }

    let changed = false
    changed = ensureAutodate(collection, 'created', { onCreate: true, onUpdate: false }) || changed
    changed = ensureAutodate(collection, 'updated', { onCreate: true, onUpdate: true }) || changed

    if (changed) {
      app.save(collection)
      console.log(`[0015] 已补齐 autodate：${name}`)
    }

    backfill(app, name)
  }

  function ensureAutodate(collection, fieldName, opts) {
    try {
      if (collection.fields.getByName(fieldName)) { return false }
    } catch (_) { /* 取不到就是没有，继续加 */ }
    collection.fields.add(new AutodateField({
      name: fieldName,
      onCreate: opts.onCreate,
      onUpdate: opts.onUpdate,
    }))
    return true
  }

  // 回填历史行。两条 UPDATE 都带「仅当为空」的条件，重复执行不会覆盖真实值。
  function backfill(app, table) {
    exec(app, `UPDATE {{${table}}} SET [[updated]] = [[clientUpdatedAt]]
               WHERE ([[updated]] IS NULL OR [[updated]] = '')
                 AND [[clientUpdatedAt]] IS NOT NULL AND [[clientUpdatedAt]] != ''`)
    exec(app, `UPDATE {{${table}}} SET [[updated]] = '${EPOCH}'
               WHERE [[updated]] IS NULL OR [[updated]] = ''`)
    exec(app, `UPDATE {{${table}}} SET [[created]] = [[updated]]
               WHERE [[created]] IS NULL OR [[created]] = ''`)
  }

  // clientUpdatedAt 不是每个集合都有（automation_jobs 等就没有），
  // 那条 UPDATE 会因为列不存在而抛错——属预期，吞掉继续跑下一条。
  function exec(app, sql) {
    try {
      app.db().newQuery(sql).execute()
    } catch (err) {
      console.log(`[0015] 回填跳过（通常是该表没有 clientUpdatedAt 列）：${err}`)
    }
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (_) { return null }
  }
}, (app) => {
  // 回滚刻意不删字段。
  // created/updated 是同步的命脉：删掉它们，每一个集合的每一次增量拉取立刻回到 400，
  // 而这正是 2026-07 那次「同步从未成功」的原样复现。多回滚一步就是全家停摆，
  // 代价远大于「留下两个字段」。与 0014 的处理方式一致。
})

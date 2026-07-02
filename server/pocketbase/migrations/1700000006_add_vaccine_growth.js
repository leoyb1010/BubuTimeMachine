/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 新增 vaccinerecords / growthmeasurements 两个集合
// 背景：早期 init 漏建这两个集合，iOS/鸿蒙端在缺集合时会降级写入 healthrecords（靠正则回填）。
//       建好后客户端自动走原生结构化路径，不再降级，数据可直接查询。
// 字段名以客户端实际收发为准：来源字段为 sourceRaw（读取侧兼容旧 source）。

migrate((app) => {
  const authRule = '@request.auth.id != ""'  // 仅登录用户可访问（与其它集合一致）

  // 通用：localId（客户端 UUID 幂等去重）+ clientUpdatedAt（增量游标）
  function baseFields(extra) {
    return [
      { name: 'localId', type: 'text', required: true, presentable: true, unique: true },
      { name: 'clientUpdatedAt', type: 'date' },
      ...extra,
    ]
  }

  // ---- vaccinerecords（疫苗记录）----
  if (!safeFind(app, 'vaccinerecords')) {
    const vaccinerecords = new Collection({
      type: 'base', name: 'vaccinerecords',
      listRule: authRule, viewRule: authRule, createRule: authRule,
      updateRule: authRule, deleteRule: authRule,
      fields: baseFields([
        { name: 'vaccineName', type: 'text', required: true },
        { name: 'injectedAt', type: 'date', required: true },
        { name: 'sourceRaw', type: 'text' },
        { name: 'doseId', type: 'text' },
        { name: 'doseLabel', type: 'text' },
        { name: 'hospital', type: 'text' },
        { name: 'injectionSite', type: 'text' },
        { name: 'reaction', type: 'text' },
        { name: 'note', type: 'text' },
      ]),
    })
    app.save(vaccinerecords)
  }

  // ---- growthmeasurements（成长测量：身高/体重/头围）----
  if (!safeFind(app, 'growthmeasurements')) {
    const growthmeasurements = new Collection({
      type: 'base', name: 'growthmeasurements',
      listRule: authRule, viewRule: authRule, createRule: authRule,
      updateRule: authRule, deleteRule: authRule,
      fields: baseFields([
        { name: 'measuredAt', type: 'date', required: true },
        { name: 'sourceRaw', type: 'text' },
        { name: 'heightCm', type: 'number' },
        { name: 'weightKg', type: 'number' },
        { name: 'headCircumferenceCm', type: 'number' },
        { name: 'note', type: 'text' },
      ]),
    })
    app.save(growthmeasurements)
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
}, (app) => {
  // 回滚：删除这两个集合
  for (const n of ['growthmeasurements', 'vaccinerecords']) {
    try { app.delete(app.findCollectionByNameOrId(n)) } catch (e) {}
  }
})

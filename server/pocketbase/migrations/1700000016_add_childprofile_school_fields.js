/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 儿童档案增加「上幼儿园第一天」与入园健康字段
//
// 纯 additive：老客户端不认识这个字段，推上来的 JSON 里没有这个键，服务端保持原值；
// 新客户端的 apply() 也只在远端确实给了值时才覆盖，不会把另一台设备刚填的日期清空。

migrate((app) => {
  const collection = app.findCollectionByNameOrId('childprofile')
  let changed = false

  if (!has(collection, 'schoolStartDate')) {
    collection.fields.add(new DateField({ name: 'schoolStartDate' }))
    changed = true
  }
  // 过敏源与健康备注：入园要填，爸妈两台手机都得看得到。
  if (!has(collection, 'allergies')) {
    collection.fields.add(new TextField({ name: 'allergies' }))
    changed = true
  }
  if (!has(collection, 'medicalNotes')) {
    collection.fields.add(new TextField({ name: 'medicalNotes' }))
    changed = true
  }

  if (changed) { app.save(collection) }

  function has(c, name) {
    try { return !!c.fields.getByName(name) } catch (_) { return false }
  }
}, (app) => {
  // 回滚保留字段：删掉会丢掉家长填过的入园日期与过敏信息，而留着对老客户端毫无影响。
  // 与 0014 / 0015 的处理方式一致。
})

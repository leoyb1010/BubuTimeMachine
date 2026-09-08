/// <reference path="../pb_data/types.d.ts" />
// 0018 在新库（尚无家庭）和多家庭库中提前返回，留下宽松规则。
// 本迁移对空库也设置严格规则；有历史无归属记录时，先验证归属再收紧。
// 家庭数不唯一时禁止猜测归属，整个迁移回滚，由维护者完成备份和明确分配后重试。
migrate((app) => {
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]
  const families = app.findRecordsByFilter('families', '', '', 2, 0)
  const orphaned = business.filter((name) =>
    app.findRecordsByFilter(name, 'familyId = ""', '', 1, 0).length > 0)
  if (orphaned.length > 0 && families.length !== 1) {
    throw new Error('[0019] 历史记录尚未分配家庭：请先备份并由管理员明确 familyId，再重试迁移。')
  }
  if (families.length === 1) {
    for (const name of orphaned) {
      app.db().newQuery(`UPDATE {{${name}}} SET [[familyId]] = {:family}
                        WHERE [[familyId]] IS NULL OR [[familyId]] = ''`)
        .bind({ family: families[0].id }).execute()
    }
    // 账号归属不做自动推断：管理员显式分配，未分配账号无法访问业务资料。
  }
  const read = '@request.auth.id != "" && @request.auth.familyId != "" && familyId = @request.auth.familyId'
  const unchangedFamily = '(@request.body.familyId:isset = false || @request.body.familyId = familyId)'
  for (const name of business) {
    const collection = app.findCollectionByNameOrId(name)
    collection.listRule = read
    collection.viewRule = read
    collection.createRule = '@request.auth.id != "" && @request.auth.familyId != "" && @request.body.familyId = @request.auth.familyId'
    collection.updateRule = read + ' && ' + unchangedFamily
    if (name === 'timecapsules') {
      collection.updateRule += ' && (@request.body.cryptoVersion:isset = false || @request.body.cryptoVersion >= cryptoVersion)'
    }
    collection.deleteRule = null
    app.save(collection)
  }
  const users = app.findCollectionByNameOrId('users')
  users.updateRule = 'id = @request.auth.id && ' + unchangedFamily
  app.save(users)
  const collection = app.findCollectionByNameOrId('families')
  collection.listRule = '@request.auth.id != "" && @request.auth.familyId != "" && id = @request.auth.familyId'
  collection.viewRule = collection.listRule
  app.save(collection)
}, () => {
  // 回滚应用版本时保留权限边界和已确认的归属；修复前进，不重新开放跨家庭访问。
})

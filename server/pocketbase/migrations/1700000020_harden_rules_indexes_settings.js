/// <reference path="../pb_data/types.d.ts" />
// 2026-09-12 审计：
// 1) 同家庭账号可把墓碑翻活（PATCH isDeleted=false）、改写 authorUserId、改自己的 role；
// 2) 同步热路径 filter(updated>…) sort(updated,id) 没有索引，GC 的 isDeleted+updated 也没有；
// 3) 走 Cloudflare 隧道时所有公网请求在 PocketBase 眼里都是 127.0.0.1，限流形同虚设且未开启。
// 只追加规则、索引与设置，不改字段、不动数据；回滚保留收紧后的边界。
migrate((app) => {
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]
  const hasField = (collection, name) => {
    try { return !!collection.fields.getByName(name) } catch (_) { return false }
  }
  // 允许把活记录改成墓碑、允许对活记录重发 isDeleted=false；禁止把墓碑翻活。
  const tombstoneGuard = '(@request.body.isDeleted:isset = false || @request.body.isDeleted = true || isDeleted = false)'
  // 作者归属一经写入不可改写；历史空值允许补齐。
  const authorGuard = '(@request.body.authorUserId:isset = false || authorUserId = "" || @request.body.authorUserId = authorUserId)'
  for (const name of business) {
    const collection = app.findCollectionByNameOrId(name)
    let rule = collection.updateRule || ''
    if (rule && hasField(collection, 'isDeleted') && !rule.includes('@request.body.isDeleted')) {
      rule += ' && ' + tombstoneGuard
    }
    if (rule && hasField(collection, 'authorUserId') && !rule.includes('@request.body.authorUserId')) {
      rule += ' && ' + authorGuard
    }
    collection.updateRule = rule
    if (hasField(collection, 'familyId')) {
      collection.addIndex('idx_' + name + '_family_updated', false, 'familyId, updated, id', '')
    }
    if (hasField(collection, 'isDeleted')) {
      collection.addIndex('idx_' + name + '_deleted_updated', false, 'isDeleted, updated', '')
    }
    app.save(collection)
  }
  const users = app.findCollectionByNameOrId('users')
  if (users.updateRule && hasField(users, 'role') && !users.updateRule.includes('@request.body.role')) {
    users.updateRule += ' && (@request.body.role:isset = false || @request.body.role = role)'
    app.save(users)
  }

  const settings = app.settings()
  // 隧道流量由 Cloudflare 覆写 CF-Connecting-IP，本地/局域网直连没有该头则回退到 socket 地址。
  settings.trustedProxy.headers = ['CF-Connecting-IP']
  settings.trustedProxy.useLeftmostIP = false
  settings.rateLimits.enabled = true
  // 只限制认证与批量端点；同步/文件读取不设总量限制，避免首轮全量同步被误伤。
  settings.rateLimits.rules = [
    { label: '*:auth', audience: '', duration: 3, maxRequests: 10 },
    { label: '/api/batch', audience: '', duration: 1, maxRequests: 3 },
    { label: '/api/files/token', audience: '', duration: 3, maxRequests: 30 },
  ]
  app.save(settings)
}, () => {
  // 回滚应用版本时保留收紧后的规则、索引和限流设置。
})

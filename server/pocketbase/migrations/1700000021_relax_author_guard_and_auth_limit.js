/// <reference path="../pb_data/types.d.ts" />
// 0020 的作者守卫（@request.body.authorUserId 必须等于原作者）在实机上会把家人之间的互相编辑/删除
// 全部 404：所有已发布客户端（iOS 2.14/2.15、鸿蒙）在 PATCH 时都会把"当前用户"注入 authorUserId。
// 作者不可篡改这条要求改由 pb_hooks/authorship.pb.js 在服务端钉住原值实现（忽略客户端的杂散值而不是拒绝）。
// 同时把认证限流从 10/3s 放宽到 30/3s：2.14 客户端 token 过期时会并发发起最多 26 次密码登录。
migrate((app) => {
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]
  const authorGuard = ' && (@request.body.authorUserId:isset = false || authorUserId = "" || @request.body.authorUserId = authorUserId)'
  for (const name of business) {
    const collection = app.findCollectionByNameOrId(name)
    if (collection.updateRule && collection.updateRule.includes(authorGuard)) {
      collection.updateRule = collection.updateRule.replace(authorGuard, '')
      app.save(collection)
    }
  }
  const settings = app.settings()
  settings.rateLimits.rules = (settings.rateLimits.rules || []).map((rule) =>
    rule.label === '*:auth' ? { label: '*:auth', audience: '', duration: 3, maxRequests: 30 } : rule)
  app.save(settings)
}, () => {
  // 不回退：回退等于重新制造 404。
})

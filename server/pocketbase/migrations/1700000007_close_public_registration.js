/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 关闭 PocketBase users 公开注册
// 新账号由超管在后台创建，客户端只负责登录。

migrate((app) => {
  const users = safeFind(app, 'users')
  if (!users) { return }

  users.createRule = null
  app.save(users)

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
}, (app) => {
  const users = safeFind(app, 'users')
  if (!users) { return }

  users.createRule = ''
  app.save(users)

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
})

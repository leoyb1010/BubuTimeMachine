/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 时间胶囊集合
// 只存加密后的 blob；信件正文、语音内容都在客户端加密后再上传。

migrate((app) => {
  const authRule = '@request.auth.id != ""'
  if (safeFind(app, 'timecapsules')) { return }

  const collection = new Collection({
    type: 'base',
    name: 'timecapsules',
    listRule: authRule,
    viewRule: authRule,
    createRule: authRule,
    updateRule: authRule,
    deleteRule: authRule,
    fields: [
      { name: 'localId', type: 'text', required: true, presentable: true, unique: true },
      { name: 'clientUpdatedAt', type: 'date' },
      { name: 'title', type: 'text', required: true },
      { name: 'fromRole', type: 'text', required: true },
      { name: 'unlockAt', type: 'date', required: true },
      { name: 'isLocked', type: 'bool' },
      { name: 'coverEmoji', type: 'text' },
      { name: 'encryptedBlob', type: 'file', maxSelect: 1, maxSize: 209715200 },
    ],
  })

  app.save(collection)

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
}, (app) => {
  // No-op: timecapsules is part of the initial schema on current cold starts.
})

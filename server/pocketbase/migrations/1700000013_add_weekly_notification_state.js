/// <reference path="../pb_data/types.d.ts" />
// 周报通知 outbox：只有 ntfy 成功后才写 notifiedAt，失败可由下次定时任务安全重试。

migrate((app) => {
  const collection = app.findCollectionByNameOrId('derived_artifacts')
  const existing = collection.fields.getByName('notifiedAt')
  if (!existing) {
    collection.fields.add(new DateField({ name: 'notifiedAt' }))
    app.save(collection)
  }
}, (app) => {
  const collection = app.findCollectionByNameOrId('derived_artifacts')
  const field = collection.fields.getByName('notifiedAt')
  if (!field) { return }
  collection.fields.removeById(field.id)
  app.save(collection)
})

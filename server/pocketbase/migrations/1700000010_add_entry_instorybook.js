/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · entries 补 inStorybook 字段
// 成长绘本重构后，记录是否「收进绘本」由用户在客户端勾选（Entry.inStorybook）。
// 服务端没有该列时 PocketBase 会静默丢弃这个字段，导致勾选无法跨设备同步。此迁移补齐。

migrate((app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('entries') } catch (e) { return }

  const exists = collection.fields.getByName('inStorybook')
  if (!exists) {
    collection.fields.add(new BoolField({ name: 'inStorybook' }))
    app.save(collection)
  }
}, (app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('entries') } catch (e) { return }
  const field = collection.fields.getByName('inStorybook')
  if (!field) { return }
  collection.fields.removeById(field.id)
  app.save(collection)
})

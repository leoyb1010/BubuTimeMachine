/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · childprofile 补 bloodType 字段
// 客户端身份卡背面会展示血型，模型 ChildProfile.bloodType 早已存在，
// 但 init_collections 漏建了服务端列，导致血型无法跨设备同步。此迁移补齐。

migrate((app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('childprofile') } catch (e) { return }

  const exists = collection.fields.getByName('bloodType')
  if (!exists) {
    collection.fields.add(new TextField({ name: 'bloodType' }))
    app.save(collection)
  }
}, (app) => {
  let collection
  try { collection = app.findCollectionByNameOrId('childprofile') } catch (e) { return }
  const field = collection.fields.getByName('bloodType')
  if (!field) { return }
  collection.fields.removeById(field.id)
  app.save(collection)
})

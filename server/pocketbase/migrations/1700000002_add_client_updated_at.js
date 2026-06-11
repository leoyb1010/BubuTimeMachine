/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 统一同步游标字段
// clientUpdatedAt 由 App 每次写入/上传时更新，用于分页增量拉取；避免依赖 PocketBase 系统 updated/created 字段。

migrate((app) => {
  const names = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules', 'feed_events',
  ]

  for (const name of names) {
    let collection
    try { collection = app.findCollectionByNameOrId(name) } catch (e) { continue }

    const exists = collection.fields.getByName('clientUpdatedAt')
    if (!exists) {
      collection.fields.add(new DateField({ name: 'clientUpdatedAt' }))
      app.save(collection)
    }

    const records = app.findRecordsByFilter(name, '', '', 5000, 0)
    for (const record of records) {
      if (record.get('clientUpdatedAt')) { continue }
      const stamp = new DateTime()
      record.set('clientUpdatedAt', stamp)
      app.save(record)
    }
  }
}, (app) => {
  const names = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules', 'feed_events',
  ]

  for (const name of names) {
    let collection
    try { collection = app.findCollectionByNameOrId(name) } catch (e) { continue }
    const field = collection.fields.getByName('clientUpdatedAt')
    if (!field) { continue }
    collection.fields.removeById(field.id)
    app.save(collection)
  }
})

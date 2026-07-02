/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 回填已有记录的 clientUpdatedAt
// 1700000002 在部分 PocketBase JS setter 场景下可能把 JS Date 字符串归一为空；这里用 DateTime 显式写入。

migrate((app) => {
  const names = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules', 'feed_events',
  ]

  const now = new DateTime(new Date().toISOString())

  for (const name of names) {
    let collection
    try { collection = app.findCollectionByNameOrId(name) } catch (e) { continue }
    if (!collection.fields.getByName('clientUpdatedAt')) { continue }

    let offset = 0
    while (true) {
      const records = app.findRecordsByFilter(name, '', '', 500, offset)
      if (!records.length) { break }
      for (const record of records) {
        if (record.getString('clientUpdatedAt') !== '') { continue }
        record.set('clientUpdatedAt', now)
        app.save(record)
      }
      offset += records.length
    }
  }
}, (app) => {
  // No-op: this migration only fills empty clientUpdatedAt values.
})

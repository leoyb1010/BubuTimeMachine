/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 同步索引与 localId 唯一约束
// PocketBase v0.23+ 不再通过 field.unique 生成真正的唯一索引，需在 collection.indexes 显式声明。
// 建唯一索引前按 localId 保留最新记录，删除旧重复，避免迁移中断。

migrate((app) => {
  const collections = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]

  for (const name of collections) {
    const collection = safeFind(app, name)
    if (!collection) { continue }

    dedupeByLocalId(app, name)
    addIndexIfPossible(app, collection, `idx_${name}_localId`, true, 'localId')
    addIndexIfPossible(app, collection, `idx_${name}_clientUpdatedAt`, false, 'clientUpdatedAt')
  }

  const relationIndexes = {
    media: ['entryLocalId'],
    comments: ['entryLocalId'],
    voicenotes: ['entryLocalId'],
    firsttimes: ['entryLocalId'],
  }
  for (const [name, fields] of Object.entries(relationIndexes)) {
    const collection = safeFind(app, name)
    if (!collection) { continue }
    for (const field of fields) {
      addIndexIfPossible(app, collection, `idx_${name}_${field}`, false, field)
    }
  }

  const dateIndexes = {
    entries: ['happenedAt'],
    milestones: ['happenedAt'],
    firsttimes: ['happenedAt'],
    voicememos: ['recordedAt'],
    healthrecords: ['recordedAt'],
    timecapsules: ['unlockAt'],
    feed_events: ['happenedAt'],
    vaccinerecords: ['injectedAt'],
    growthmeasurements: ['measuredAt'],
  }
  for (const [name, fields] of Object.entries(dateIndexes)) {
    const collection = safeFind(app, name)
    if (!collection) { continue }
    for (const field of fields) {
      addIndexIfPossible(app, collection, `idx_${name}_${field}`, false, field)
    }
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }

  function hasField(collection, field) {
    try { return !!collection.fields.getByName(field) } catch (e) { return false }
  }

  function hasIndex(collection, indexName) {
    return (collection.indexes || []).some((sql) => new RegExp(`\\b${indexName}\\b`).test(sql))
  }

  function addIndexIfPossible(app, collection, indexName, unique, field) {
    if (!hasField(collection, field) || hasIndex(collection, indexName)) { return }
    collection.addIndex(indexName, unique, field, '')
    app.save(collection)
  }

  function dedupeByLocalId(app, collectionName) {
    const all = []
    const seen = {}
    let offset = 0
    while (true) {
      const records = app.findRecordsByFilter(collectionName, '', '', 500, offset)
      if (!records.length) { break }
      all.push(...records)
      offset += records.length
    }
    for (const record of all) {
      const localId = record.getString('localId')
      if (!localId) { continue }
      const current = seen[localId]
      if (!current) {
        seen[localId] = record
        continue
      }
      const keep = newerRecord(current, record)
      const drop = keep.id === current.id ? record : current
      seen[localId] = keep
      app.delete(drop)
    }
  }

  function newerRecord(a, b) {
    return sortStamp(b) > sortStamp(a) ? b : a
  }

  function sortStamp(record) {
    return record.getString('clientUpdatedAt') || record.getString('updated') || record.getString('created') || ''
  }
}, (app) => {
  const indexNames = [
    'idx_entries_localId', 'idx_entries_clientUpdatedAt', 'idx_entries_happenedAt',
    'idx_media_localId', 'idx_media_clientUpdatedAt', 'idx_media_entryLocalId',
    'idx_comments_localId', 'idx_comments_clientUpdatedAt', 'idx_comments_entryLocalId',
    'idx_voicenotes_localId', 'idx_voicenotes_clientUpdatedAt', 'idx_voicenotes_entryLocalId',
    'idx_milestones_localId', 'idx_milestones_clientUpdatedAt', 'idx_milestones_happenedAt',
    'idx_firsttimes_localId', 'idx_firsttimes_clientUpdatedAt', 'idx_firsttimes_entryLocalId', 'idx_firsttimes_happenedAt',
    'idx_voicememos_localId', 'idx_voicememos_clientUpdatedAt', 'idx_voicememos_recordedAt',
    'idx_members_localId', 'idx_members_clientUpdatedAt',
    'idx_childprofile_localId', 'idx_childprofile_clientUpdatedAt',
    'idx_healthrecords_localId', 'idx_healthrecords_clientUpdatedAt', 'idx_healthrecords_recordedAt',
    'idx_timecapsules_localId', 'idx_timecapsules_clientUpdatedAt', 'idx_timecapsules_unlockAt',
    'idx_feed_events_localId', 'idx_feed_events_clientUpdatedAt', 'idx_feed_events_happenedAt',
    'idx_vaccinerecords_localId', 'idx_vaccinerecords_clientUpdatedAt', 'idx_vaccinerecords_injectedAt',
    'idx_growthmeasurements_localId', 'idx_growthmeasurements_clientUpdatedAt', 'idx_growthmeasurements_measuredAt',
  ]

  for (const name of [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]) {
    const collection = safeFind(app, name)
    if (!collection) { continue }
    collection.indexes = (collection.indexes || []).filter((sql) => {
      return !indexNames.some((indexName) => new RegExp(`\\b${indexName}\\b`).test(sql))
    })
    app.save(collection)
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
})

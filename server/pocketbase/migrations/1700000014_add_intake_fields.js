/// <reference path="../pb_data/types.d.ts" />
// Reliable intake provenance. Additive only: existing facts and files are untouched.

migrate((app) => {
  const entries = app.findCollectionByNameOrId('entries')
  const media = app.findCollectionByNameOrId('media')

  ensureText(entries, 'intakeBatchId')
  ensureText(entries, 'sourceRaw')
  ensureText(media, 'intakeBatchId')
  ensureText(media, 'sourceAssetKey')
  ensureText(media, 'contentHash')
  ensureText(media, 'sourceRaw')
  ensureText(media, 'resourceRole')
  ensureText(media, 'assetGroupId')

  // PocketBase 0.39 必须先把新字段落到 SQL 表，再创建引用这些列的索引。
  // 同一次 save 中同时加字段和索引会在索引阶段报 no such column。
  app.save(entries)
  app.save(media)

  addIndex(entries, 'idx_entries_intake_batch', 'intakeBatchId')
  addIndex(media, 'idx_media_intake_batch', 'intakeBatchId')
  addIndex(media, 'idx_media_content_hash', 'familyId,contentHash')

  app.save(entries)
  app.save(media)

  function ensureText(collection, name) {
    try {
      if (collection.fields.getByName(name)) return
    } catch (_) {}
    collection.fields.add(new TextField({ name }))
  }

  function addIndex(collection, name, fields) {
    if ((collection.indexes || []).some((sql) => sql.indexOf(name) >= 0)) return
    collection.addIndex(name, false, fields, '')
  }
}, (app) => {
  // Purely additive fields intentionally remain on downgrade; deleting provenance
  // would make a rollback less safe and does not affect older clients.
})

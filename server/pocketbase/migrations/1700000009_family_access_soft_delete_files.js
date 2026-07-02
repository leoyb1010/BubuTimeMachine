/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 家庭访问字段、软删除与文件保护
// 兼容策略：
// - 老数据 familyId 为空仍可被已登录用户读取，避免升级后把历史记录锁死。
// - 新客户端会写入 authorUserId/familyId；后续可在数据回填完成后进一步收紧规则。
// - 客户端删除改为 PATCH tombstone，deleteRule 只留给超管。

migrate((app) => {
  const authRule = '@request.auth.id != ""'
  const familyRule = '@request.auth.id != "" && (@request.auth.familyId = "" || familyId = "" || familyId = @request.auth.familyId)'
  const familyCreateRule = '@request.auth.id != "" && (@request.auth.familyId = "" || @request.body.familyId = "" || @request.body.familyId = @request.auth.familyId)'

  ensureFamiliesCollection(app)
  ensureUsersCollection(app)

  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]

  for (const name of business) {
    const collection = safeFind(app, name)
    if (!collection) { continue }

    ensureTextField(collection, 'familyId')
    ensureTextField(collection, 'authorUserId')
    ensureBoolField(collection, 'isDeleted')
    ensureDateField(collection, 'deletedAt')
    ensureTextField(collection, 'deletedByUserId')

    collection.listRule = familyRule
    collection.viewRule = familyRule
    collection.createRule = familyCreateRule
    collection.updateRule = familyRule
    collection.deleteRule = null

    for (const fileField of fileFields(name)) {
      protectFileField(collection, fileField)
    }

    addIndexIfPossible(collection, `idx_${name}_familyId`, false, 'familyId')
    addIndexIfPossible(collection, `idx_${name}_isDeleted`, false, 'isDeleted')

    app.save(collection)
  }

  function ensureFamiliesCollection(app) {
    let collection = safeFind(app, 'families')
    if (!collection) {
      collection = new Collection({
        type: 'base',
        name: 'families',
        listRule: '@request.auth.id != "" && (@request.auth.familyId = "" || id = @request.auth.familyId)',
        viewRule: '@request.auth.id != "" && (@request.auth.familyId = "" || id = @request.auth.familyId)',
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: [
          { name: 'name', type: 'text', required: true },
          { name: 'code', type: 'text' },
        ],
      })
      app.save(collection)
    }
  }

  function ensureUsersCollection(app) {
    let users = safeFind(app, 'users')
    if (!users) {
      users = new Collection({
        type: 'auth',
        name: 'users',
        authRule: '',
        listRule: 'id = @request.auth.id',
        viewRule: 'id = @request.auth.id',
        createRule: null,
        updateRule: 'id = @request.auth.id',
        deleteRule: null,
        fields: [
          { name: 'name', type: 'text' },
          { name: 'role', type: 'text' },
          { name: 'familyId', type: 'text' },
        ],
      })
      app.save(users)
      return
    }

    ensureTextField(users, 'name')
    ensureTextField(users, 'role')
    ensureTextField(users, 'familyId')
    users.authRule = ''
    users.listRule = 'id = @request.auth.id'
    users.viewRule = 'id = @request.auth.id'
    users.createRule = null
    users.updateRule = 'id = @request.auth.id'
    users.deleteRule = null
    addIndexIfPossible(users, 'idx_users_familyId', false, 'familyId')
    app.save(users)
  }

  function fileFields(collectionName) {
    switch (collectionName) {
      case 'media': return ['file', 'thumbnail']
      case 'comments': return ['voiceFile']
      case 'voicenotes': return ['file']
      case 'voicememos': return ['file']
      case 'childprofile': return ['avatar', 'heroBackground']
      case 'timecapsules': return ['encryptedBlob']
      default: return []
    }
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }

  function safeField(collection, name) {
    try { return collection.fields.getByName(name) } catch (e) { return null }
  }

  function ensureTextField(collection, name) {
    if (safeField(collection, name)) { return false }
    collection.fields.add(new TextField({ name }))
    return true
  }

  function ensureBoolField(collection, name) {
    if (safeField(collection, name)) { return false }
    collection.fields.add(new BoolField({ name }))
    return true
  }

  function ensureDateField(collection, name) {
    if (safeField(collection, name)) { return false }
    collection.fields.add(new DateField({ name }))
    return true
  }

  function protectFileField(collection, name) {
    const field = safeField(collection, name)
    if (!field || typeof field.protected !== 'boolean' || field.protected) { return false }
    field.protected = true
    return true
  }

  function hasIndex(collection, indexName) {
    return (collection.indexes || []).some((sql) => new RegExp(`\\b${indexName}\\b`).test(sql))
  }

  function addIndexIfPossible(collection, indexName, unique, field) {
    if (!safeField(collection, field) || hasIndex(collection, indexName)) { return }
    collection.addIndex(indexName, unique, field, '')
  }
}, (app) => {
  const authRule = '@request.auth.id != ""'
  const business = [
    'entries', 'media', 'comments', 'voicenotes', 'milestones', 'firsttimes',
    'voicememos', 'members', 'childprofile', 'healthrecords', 'timecapsules',
    'feed_events', 'vaccinerecords', 'growthmeasurements',
  ]

  for (const name of business) {
    const collection = safeFind(app, name)
    if (!collection) { continue }
    collection.listRule = authRule
    collection.viewRule = authRule
    collection.createRule = authRule
    collection.updateRule = authRule
    collection.deleteRule = authRule
    app.save(collection)
  }

  const families = safeFind(app, 'families')
  if (families) { app.delete(families) }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
})

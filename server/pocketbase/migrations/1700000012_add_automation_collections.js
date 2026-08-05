/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 派生任务与作品集合
// 0012：生产 mini 已有历史 0011_add_autodate_fields.js，绝不能复用同一迁移序号。
//
// 安全边界：两张表均不向家庭客户端开放。所有 API rule 保持 null，只有 PocketBase
// superuser / 服务端 worker 可以读写；照片索引和 AI 产物不能被普通 App 账号枚举或篡改。

migrate((app) => {
  ensureAutomationJobs(app)
  ensureDerivedArtifacts(app)

  function ensureAutomationJobs(app) {
    let collection = safeFind(app, 'automation_jobs')
    if (!collection) {
      collection = new Collection({
        type: 'base',
        name: 'automation_jobs',
        listRule: null,
        viewRule: null,
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: [
          { name: 'jobKey', type: 'text', required: true, presentable: true },
          { name: 'kind', type: 'text', required: true },
          { name: 'sourceCollection', type: 'text', required: true },
          { name: 'sourceRecordId', type: 'text', required: true },
          { name: 'sourceLocalId', type: 'text' },
          { name: 'familyId', type: 'text' },
          { name: 'state', type: 'text', required: true },
          { name: 'attempts', type: 'number' },
          { name: 'availableAt', type: 'date' },
          { name: 'leaseOwner', type: 'text' },
          { name: 'leaseUntil', type: 'date' },
          { name: 'lastError', type: 'text' },
          { name: 'payload', type: 'json' },
          { name: 'modelVersion', type: 'text' },
        ],
      })
      collection.addIndex('idx_automation_jobs_jobKey', true, 'jobKey', '')
      collection.addIndex('idx_automation_jobs_claim', false, 'state, availableAt, leaseUntil', '')
      app.save(collection)
      return
    }
    lockToServiceAccount(collection)
    app.save(collection)
  }

  function ensureDerivedArtifacts(app) {
    let collection = safeFind(app, 'derived_artifacts')
    if (!collection) {
      collection = new Collection({
        type: 'base',
        name: 'derived_artifacts',
        listRule: null,
        viewRule: null,
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: [
          { name: 'artifactKey', type: 'text', required: true, presentable: true },
          { name: 'kind', type: 'text', required: true },
          { name: 'familyId', type: 'text' },
          { name: 'status', type: 'text', required: true },
          { name: 'title', type: 'text' },
          { name: 'summary', type: 'text' },
          { name: 'sourceRefs', type: 'json', required: true },
          { name: 'payload', type: 'json' },
          { name: 'file', type: 'file', maxSelect: 1, maxSize: 524288000, protected: true },
          { name: 'generatedAt', type: 'date' },
          { name: 'modelVersion', type: 'text' },
        ],
      })
      collection.addIndex('idx_derived_artifacts_artifactKey', true, 'artifactKey', '')
      collection.addIndex('idx_derived_artifacts_kind', false, 'kind, generatedAt', '')
      app.save(collection)
      return
    }
    lockToServiceAccount(collection)
    const file = safeField(collection, 'file')
    if (file && typeof file.protected === 'boolean') { file.protected = true }
    app.save(collection)
  }

  function lockToServiceAccount(collection) {
    collection.listRule = null
    collection.viewRule = null
    collection.createRule = null
    collection.updateRule = null
    collection.deleteRule = null
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }

  function safeField(collection, name) {
    try { return collection.fields.getByName(name) } catch (e) { return null }
  }
}, (app) => {
  for (const name of ['automation_jobs', 'derived_artifacts']) {
    const collection = safeFind(app, name)
    if (collection) { app.delete(collection) }
  }

  function safeFind(app, name) {
    try { return app.findCollectionByNameOrId(name) } catch (e) { return null }
  }
})

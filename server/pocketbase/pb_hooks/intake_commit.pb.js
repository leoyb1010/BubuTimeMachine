/// <reference path="../pb_data/types.d.ts" />
// Atomic promotion from the AI service's isolated staging area into Entry + Media facts.
// This route is loopback-only in deployment and additionally requires a 32+ byte service key.

routerAdd('POST', '/api/bubu/intake/commit', (e) => {
    const field = (value, name) => {
        if (!value) return undefined
        return typeof value.get === 'function' ? value.get(name) : value[name]
    }
    const configuredKey = ($os.getenv('INTAKE_COMMIT_KEY') || '').trim()
    const providedKey = (e.request.header.get('X-Bubu-Intake-Key') || '').trim()
    if (configuredKey.length < 32 || providedKey !== configuredKey) {
        throw new UnauthorizedError('invalid intake service key')
    }
    const remote = e.realIP()
    if (remote !== '127.0.0.1' && remote !== '::1') {
        throw new ForbiddenError('intake commit is loopback only')
    }

    const body = new DynamicModel({
        id: '', owner: '', family_id: '', state: '', entry: {}, items: [],
    })
    e.bindBody(body)
    const batchId = String(body.id || '')
    const familyId = String(body.family_id || '')
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(batchId)
        || !/^[A-Za-z0-9_-]{8,128}$/.test(familyId)
        || body.state !== 'committing') {
        throw new BadRequestError('invalid intake manifest')
    }
    if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 500) {
        throw new BadRequestError('invalid intake item count')
    }

    const existingEntries = e.app.findRecordsByFilter(
        'entries', 'intakeBatchId={:batch}', '', 1, 0, { batch: batchId }
    )
    if (existingEntries.length > 0) {
        return e.json(200, { entry_id: existingEntries[0].id, idempotent: true })
    }

    const stagingRoot = ($os.getenv('INTAKE_STAGING_ROOT') || '').replace(/\/$/, '')
    const allowedPrefix = stagingRoot + '/files/' + batchId + '/'
    if (!stagingRoot || stagingRoot.length < 4) {
        throw new InternalServerError('staging root is not configured')
    }

    let entryId = ''
    e.app.runInTransaction((txApp) => {
        const entryData = body.entry || {}
        const entryLocalId = String(field(entryData, 'local_id') || batchId)
        if (!/^[A-Za-z0-9_-]{8,128}$/.test(entryLocalId)) {
            throw new BadRequestError('invalid entry local id')
        }
        const freshItems = []
        for (const item of body.items) {
            const digest = String(field(item, 'content_hash') || '')
            if (!/^[0-9a-f]{64}$/.test(digest)) {
                throw new BadRequestError('invalid staged item hash')
            }
            const duplicates = txApp.findRecordsByFilter(
                'media',
                'familyId={:family} && contentHash={:digest} && isDeleted=false',
                '', 100, 0, { family: familyId, digest: digest }
            )
            let activeEntry = null
            for (const duplicate of duplicates) {
                const candidateEntries = txApp.findRecordsByFilter(
                    'entries', 'familyId={:family} && localId={:local}', '', 1, 0,
                    { family: familyId, local: duplicate.getString('entryLocalId') }
                )
                if (candidateEntries.length === 0) continue
                const candidateEntry = candidateEntries[0]
                if (!candidateEntry.getBool('isArchived') && !candidateEntry.getBool('isDeleted')) {
                    activeEntry = candidateEntry
                    break
                }
            }
            if (!activeEntry) {
                freshItems.push(item)
            } else if (!entryId) {
                entryId = activeEntry.id
            }
        }
        // 同一原片已由 SSD、另一台手机或此前批次收录时，不制造空 Entry；
        // 返回已有事实，由 staging 正常收口并清理本批中转文件。
        if (freshItems.length === 0) return

        const entry = new Record(txApp.findCollectionByNameOrId('entries'))
        entry.set('localId', entryLocalId)
        entry.set('familyId', familyId)
        entry.set('authorUserId', String(body.owner || '').replace(/^pb:/, ''))
        entry.set('happenedAt', String(field(entryData, 'happened_at') || ''))
        entry.set('happenedAtClient', String(field(entryData, 'happened_at') || ''))
        entry.set('authorRole', String(field(entryData, 'author_role') || '爸爸'))
        entry.set('note', String(field(entryData, 'note') || ''))
        entry.set('title', String(field(entryData, 'title') || ''))
        entry.set('locationName', String(field(entryData, 'location_name') || ''))
        entry.set('isArchived', false)
        entry.set('isDeleted', false)
        entry.set('intakeBatchId', batchId)
        entry.set('sourceRaw', String(field(entryData, 'source') || 'iphone-photo-library'))
        entry.set('clientUpdatedAt', new Date().toISOString())
        txApp.save(entry)
        entryId = entry.id

        for (const item of freshItems) {
            const assetKey = String(field(item, 'asset_key') || '')
            const storedPath = String(field(item, 'stored_path') || '')
            const digest = String(field(item, 'content_hash') || '')
            if (!/^[A-Za-z0-9_-]{8,128}$/.test(assetKey)
                || !/^[0-9a-f]{64}$/.test(digest)
                || storedPath.indexOf(allowedPrefix) !== 0
                || storedPath.indexOf('/../') >= 0) {
                throw new BadRequestError('invalid staged item')
            }
            const file = $filesystem.fileFromPath(storedPath)
            const media = new Record(txApp.findCollectionByNameOrId('media'))
            media.set('localId', assetKey)
            media.set('entryLocalId', entryLocalId)
            media.set('familyId', familyId)
            media.set('authorUserId', String(body.owner || '').replace(/^pb:/, ''))
            media.set('mediaType', String(field(item, 'media_type') || 'photo'))
            media.set('file', file)
            media.set('contentHash', digest)
            media.set('intakeBatchId', batchId)
            media.set('sourceAssetKey', assetKey)
            media.set('sourceRaw', String(field(entryData, 'source') || 'iphone-photo-library'))
            media.set('resourceRole', String(field(item, 'resource_role') || 'original'))
            media.set('assetGroupId', String(field(item, 'asset_group_id') || assetKey))
            media.set('isDeleted', false)
            media.set('clientUpdatedAt', new Date().toISOString())
            txApp.save(media)
        }
    })
    return e.json(201, { entry_id: entryId, idempotent: false })
})

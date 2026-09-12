/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 墓碑文件回收（GC）
// 客户端删除走软删除（isDeleted=true 的墓碑），保证删除能跨设备传播。
// 以前 GC 把超过保留期的墓碑整行真删，但客户端并没有“离线超期就全量对账”的逻辑：
// 一台 30 天没开的手机上线后编辑/重传，会把全家已删除的照片 POST 回来（复活）。
// 现在墓碑行永久保留（几百字节），只回收其挂载的文件（照片/视频/音频/封面）释放磁盘。
// 没有文件字段的集合墓碑本身就不占空间，不再处理。
//
// 配置（环境变量，可选）：
//   BUBU_GC_RETENTION_DAYS  文件保留天数，默认 30（给全家设备留足下载/同步窗口）
//   BUBU_GC_BATCH           单次最多处理条数，默认 200
// 运维入口：POST /api/bubu/ops/tombstone-gc（仅 superuser，body 可带 {"retentionDays":N}）用于演练与测试。

cronAdd("bubu_tombstone_gc", "0 4 * * *", () => {
    const retentionDays = parseInt($os.getenv("BUBU_GC_RETENTION_DAYS") || "30", 10);
    const batch = parseInt($os.getenv("BUBU_GC_BATCH") || "200", 10);
    const cutoff = new Date(Date.now() - retentionDays * 24 * 3600 * 1000)
        .toISOString().replace("T", " ");
    const collections = [
        "entries", "media", "comments", "voicenotes", "milestones",
        "firsttimes", "voicememos", "members", "childprofile",
        "healthrecords", "timecapsules", "vaccinerecords", "growthmeasurements", "feed_events",
    ];
    let purged = 0;
    for (const name of collections) {
        try {
            const collection = $app.findCollectionByNameOrId(name);
            const fileFields = [];
            for (let i = 0; i < collection.fields.length; i++) {
                const field = collection.fields[i];
                if (field.type() === "file") fileFields.push(field.name);
            }
            if (fileFields.length === 0) continue;
            const hasFile = fileFields.map((f) => f + " != ''").join(" || ");
            const stale = $app.findRecordsByFilter(
                name,
                `isDeleted = true && updated < "${cutoff}" && (${hasFile})`,
                "updated", batch, 0
            );
            for (const record of stale) {
                try {
                    for (const f of fileFields) { record.set(f, null); }
                    $app.save(record);   // 保留墓碑行，PocketBase 删除卸下的文件
                    purged++;
                } catch (err) {
                    console.log(`[bubu-gc] purge failed ${name}/${record.id}:`, err);
                }
            }
        } catch (err) {
            console.log(`[bubu-gc] skipped ${name}:`, err);
        }
    }
    if (purged > 0) {
        console.log(`[bubu-gc] purged files of ${purged} tombstones older than ${retentionDays}d`);
    }
});

routerAdd("POST", "/api/bubu/ops/tombstone-gc", (e) => {
    if (!e.auth || !e.auth.isSuperuser()) {
        throw new ForbiddenError("superuser only");
    }
    const body = new DynamicModel({ retentionDays: -1 });
    try { e.bindBody(body); } catch (_) { /* 空 body 使用默认 */ }
    const envDays = parseInt($os.getenv("BUBU_GC_RETENTION_DAYS") || "30", 10);
    const retentionDays = body.retentionDays >= 0 ? Number(body.retentionDays) : envDays;
    const batch = parseInt($os.getenv("BUBU_GC_BATCH") || "200", 10);
    const cutoff = new Date(Date.now() - retentionDays * 24 * 3600 * 1000)
        .toISOString().replace("T", " ");
    const collections = [
        "entries", "media", "comments", "voicenotes", "milestones",
        "firsttimes", "voicememos", "members", "childprofile",
        "healthrecords", "timecapsules", "vaccinerecords", "growthmeasurements", "feed_events",
    ];
    let purged = 0;
    const errors = [];
    for (const name of collections) {
        try {
            const collection = $app.findCollectionByNameOrId(name);
            const fileFields = [];
            for (let i = 0; i < collection.fields.length; i++) {
                const field = collection.fields[i];
                if (field.type() === "file") fileFields.push(field.name);
            }
            if (fileFields.length === 0) continue;
            const hasFile = fileFields.map((f) => f + " != ''").join(" || ");
            const stale = $app.findRecordsByFilter(
                name,
                `isDeleted = true && updated < "${cutoff}" && (${hasFile})`,
                "updated", batch, 0
            );
            for (const record of stale) {
                try {
                    for (const f of fileFields) { record.set(f, null); }
                    $app.save(record);
                    purged++;
                } catch (err) {
                    errors.push(name + "/" + record.id);
                }
            }
        } catch (err) {
            errors.push(name + ": " + String(err));
        }
    }
    return e.json(200, { purged: purged, retentionDays: retentionDays, errors: errors });
});

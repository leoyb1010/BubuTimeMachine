/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 墓碑回收（GC）
// 客户端删除走软删除（isDeleted=true 的墓碑），保证删除能跨设备传播；
// 但 PocketBase 的文件生命周期绑定 record——record 永不真删，删掉的照片/视频
// 会永远占着服务器磁盘。本 cron 每天凌晨把「已软删且超过保留期」的墓碑真删，
// PocketBase 级联删除其文件，磁盘得以回收。
//
// 保留期 30 天：给全家所有设备留足同步窗口（墓碑被拉走并本地删除后即无用）；
// 30 天没开过 App 的设备重新上线时走全量拉取，不依赖墓碑，因此真删是安全的。
//
// 配置（环境变量，可选）：
//   BUBU_GC_RETENTION_DAYS  保留天数，默认 30
//   BUBU_GC_BATCH           单次最多删除条数，默认 200（分批温和回收，不冲击磁盘 IO）

cronAdd("bubu_tombstone_gc", "0 4 * * *", () => {
    const retentionDays = parseInt($os.getenv("BUBU_GC_RETENTION_DAYS") || "30", 10);
    const batch = parseInt($os.getenv("BUBU_GC_BATCH") || "200", 10);
    const cutoff = new Date(Date.now() - retentionDays * 24 * 3600 * 1000)
        .toISOString().replace("T", " ");

    const collections = [
        "entries", "media", "comments", "voicenotes", "milestones",
        "firsttimes", "voicememos", "members", "childprofile",
        "healthrecords", "timecapsules", "vaccinerecords", "growthmeasurements",
    ];

    let removed = 0;
    for (const name of collections) {
        try {
            const stale = $app.findRecordsByFilter(
                name,
                `isDeleted = true && updated < "${cutoff}"`,
                "updated",
                batch,
                0
            );
            for (const record of stale) {
                try {
                    $app.delete(record);   // 级联删除挂载的文件（file/thumbnail）
                    removed++;
                } catch (err) {
                    console.log(`[bubu-gc] delete failed ${name}/${record.id}:`, err);
                }
            }
        } catch (err) {
            // 集合不存在（老库）或查询失败：跳过，不影响其它集合
        }
    }
    if (removed > 0) {
        console.log(`[bubu-gc] reclaimed ${removed} tombstones older than ${retentionDays}d`);
    }
});

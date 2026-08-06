/// <reference path="../pb_data/types.d.ts" />
// media 变化时只投递幂等任务；模型计算由 mini worker 完成，绝不阻塞 PocketBase 写入。
// PocketBase hook pool 不保留文件级 helper，处理函数必须把 enqueue 定义在回调内部。

onRecordAfterCreateSuccess((e) => {
    function enqueue(record, kind) {
        const mediaType = record.getString("mediaType");
        if (mediaType !== "photo" && mediaType !== "video") return;
        const role = record.getString("resourceRole");
        if (kind === "semantic_media_upsert" && role && role !== "display") return;
        const collection = $app.findCollectionByNameOrId("automation_jobs");
        const job = new Record(collection);
        job.set("jobKey", "semantic_media:" + record.id + ":" + Date.now() + ":" + $security.randomString(8));
        job.set("kind", kind);
        job.set("sourceCollection", "media");
        job.set("sourceRecordId", record.id);
        job.set("sourceLocalId", record.getString("localId"));
        job.set("familyId", record.getString("familyId"));
        job.set("state", "queued");
        job.set("attempts", 0);
        job.set("availableAt", new Date().toISOString());
        job.set("leaseOwner", "");
        job.set("leaseUntil", "");
        job.set("lastError", "");
        job.set("modelVersion", $os.getenv("SEMANTIC_MODEL_VERSION") || "mobileclip-s0-datacompdr-1b");
        job.set("payload", { "mediaRecordId": record.id });
        $app.save(job);
    }

    try {
        const kind = e.record.getBool("isDeleted")
            ? "semantic_media_delete" : "semantic_media_upsert";
        enqueue(e.record, kind);
    } catch (err) {
        // 派生任务失败不能让事实记录写入看起来失败；保留日志，后续全量扫描可补建。
        console.log("[bubu-semantic] enqueue failed:", err);
    }
    e.next();
}, "media");

onRecordAfterUpdateSuccess((e) => {
    function enqueue(record, kind) {
        const mediaType = record.getString("mediaType");
        if (mediaType !== "photo" && mediaType !== "video") return;
        const role = record.getString("resourceRole");
        if (kind === "semantic_media_upsert" && role && role !== "display") return;
        const collection = $app.findCollectionByNameOrId("automation_jobs");
        const job = new Record(collection);
        job.set("jobKey", "semantic_media:" + record.id + ":" + Date.now() + ":" + $security.randomString(8));
        job.set("kind", kind);
        job.set("sourceCollection", "media");
        job.set("sourceRecordId", record.id);
        job.set("sourceLocalId", record.getString("localId"));
        job.set("familyId", record.getString("familyId"));
        job.set("state", "queued");
        job.set("attempts", 0);
        job.set("availableAt", new Date().toISOString());
        job.set("leaseOwner", "");
        job.set("leaseUntil", "");
        job.set("lastError", "");
        job.set("modelVersion", $os.getenv("SEMANTIC_MODEL_VERSION") || "mobileclip-s0-datacompdr-1b");
        job.set("payload", { "mediaRecordId": record.id });
        $app.save(job);
    }

    try {
        const kind = e.record.getBool("isDeleted")
            ? "semantic_media_delete" : "semantic_media_upsert";
        enqueue(e.record, kind);
    } catch (err) {
        console.log("[bubu-semantic] enqueue failed:", err);
    }
    e.next();
}, "media");

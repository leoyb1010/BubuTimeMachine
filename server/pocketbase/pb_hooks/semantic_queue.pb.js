/// <reference path="../pb_data/types.d.ts" />
// media 变化时只投递幂等任务；模型计算由 mini worker 完成，绝不阻塞 PocketBase 写入。
// PocketBase hook pool 不保留文件级 helper，处理函数必须把 enqueue 定义在回调内部。
//
// 2026-09-12：jobKey 改为由「记录 + 任务类型 + 文件/缩略图/角色」确定性生成。
// 以前每次任何字段更新（宽高回填、clientUpdatedAt、同步触碰）都随机新建一条任务，
// 一张照片会被重复嵌入多次且队列永不收敛；现在无关更新不入队，同一内容只排一次。

onRecordAfterCreateSuccess((e) => {
    function enqueue(record, kind) {
        const mediaType = record.getString("mediaType");
        if (mediaType !== "photo" && mediaType !== "video") return;
        const role = record.getString("resourceRole");
        if (kind === "semantic_media_upsert" && role && role !== "display") return;
        const content = record.getString("file") + "|" + record.getString("thumbnail") + "|" + role;
        const jobKey = "semantic_media:" + record.id + ":" + kind + ":" + $security.sha256(content).slice(0, 16);
        const collection = $app.findCollectionByNameOrId("automation_jobs");
        let job;
        try {
            job = $app.findFirstRecordByData("automation_jobs", "jobKey", jobKey);
        } catch (_) { job = null; }
        if (job) {
            const state = job.getString("state");
            if (state === "queued" || state === "running") return;
            // 同一内容此前已处理过又再次出现（如删除后撤销）：重排而不是新建。
            job.set("state", "queued");
            job.set("attempts", 0);
            job.set("availableAt", new Date().toISOString());
            job.set("leaseOwner", "");
            job.set("leaseUntil", "");
            job.set("lastError", "");
            $app.save(job);
            return;
        }
        job = new Record(collection);
        job.set("jobKey", jobKey);
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
        const content = record.getString("file") + "|" + record.getString("thumbnail") + "|" + role;
        const jobKey = "semantic_media:" + record.id + ":" + kind + ":" + $security.sha256(content).slice(0, 16);
        const collection = $app.findCollectionByNameOrId("automation_jobs");
        let job;
        try {
            job = $app.findFirstRecordByData("automation_jobs", "jobKey", jobKey);
        } catch (_) { job = null; }
        if (job) {
            const state = job.getString("state");
            if (state === "queued" || state === "running") return;
            job.set("state", "queued");
            job.set("attempts", 0);
            job.set("availableAt", new Date().toISOString());
            job.set("leaseOwner", "");
            job.set("leaseUntil", "");
            job.set("lastError", "");
            $app.save(job);
            return;
        }
        job = new Record(collection);
        job.set("jobKey", jobKey);
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
        // 只有影响索引结果的字段变了才入队：文件、缩略图、删除态、资源角色、类型。
        const watched = ["file", "thumbnail", "isDeleted", "resourceRole", "mediaType"];
        let changed = false;
        let original = null;
        try { original = e.record.original(); } catch (_) { original = null; }
        if (!original) {
            changed = true;
        } else {
            for (const name of watched) {
                if (String(e.record.get(name)) !== String(original.get(name))) { changed = true; break; }
            }
        }
        if (changed) {
            const kind = e.record.getBool("isDeleted")
                ? "semantic_media_delete" : "semantic_media_upsert";
            enqueue(e.record, kind);
        }
    } catch (err) {
        console.log("[bubu-semantic] enqueue failed:", err);
    }
    e.next();
}, "media");

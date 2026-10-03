// No mutable module state: PocketBase shares loaded modules between hook runtimes.
// The signature includes actual worker inputs, never updated/clientUpdatedAt,
// dimensions or sync bookkeeping. A changed signature can queue behind a running
// older job, and the worker always rereads current facts before updating the index.
function mediaInput(record) {
    return [record.getString("file"), record.getString("thumbnail"),
        record.getBool("isDeleted"), record.getString("resourceRole") || "display",
        record.getString("mediaType"), record.getString("entryLocalId"),
        record.getString("familyId"), record.get("aiTags") || [], record.getString("created")];
}

function entryInput(record) {
    if (!record) return null;
    return [record.id, record.getString("localId"), record.getString("familyId"),
        record.getString("title"), record.getString("note"), record.getString("firstPersonNote"),
        record.getString("locationName"), record.getString("happenedAt"), record.getBool("isDeleted")];
}

function searchable(record) {
    if (!record) return false;
    const mediaType = record.getString("mediaType");
    if (mediaType !== "photo" && mediaType !== "video") return false;
    return (record.getString("resourceRole") || "display") === "display";
}

function entryFor(app, family, local) {
    const entries = app.findRecordsByFilter("entries",
        "localId={:local} && familyId={:family}", "", 1, 0,
        { local: local, family: family });
    return entries.length ? entries[0] : null;
}

function enqueue(app, media, entry, wasSearchable) {
    if (!searchable(media) && !wasSearchable) return;
    const kind = !searchable(media) || media.getBool("isDeleted") || !entry || entry.getBool("isDeleted")
        ? "semantic_media_delete" : "semantic_media_upsert";
    const content = JSON.stringify([mediaInput(media), entryInput(entry)]);
    const jobKey = "semantic_media:" + media.id + ":" + kind + ":" + $security.sha256(content).slice(0, 24);
    let job;
    try { job = app.findFirstRecordByData("automation_jobs", "jobKey", jobKey); }
    catch (_) { job = null; }
    if (job && (job.getString("state") === "queued" || job.getString("state") === "running")) return;
    if (!job) {
        job = new Record(app.findCollectionByNameOrId("automation_jobs"));
        job.set("jobKey", jobKey);
    }
    // Revisiting an old signature (e.g. undoing an admin deletion) reuses its row.
    job.set("kind", kind);
    job.set("sourceCollection", "media");
    job.set("sourceRecordId", media.id);
    job.set("sourceLocalId", media.getString("localId"));
    job.set("familyId", media.getString("familyId"));
    job.set("state", "queued");
    job.set("attempts", 0);
    job.set("availableAt", new Date().toISOString());
    job.set("leaseOwner", "");
    job.set("leaseUntil", "");
    job.set("lastError", "");
    job.set("modelVersion", $os.getenv("SEMANTIC_MODEL_VERSION") || "mobileclip-s0-datacompdr-1b");
    job.set("payload", { mediaRecordId: media.id });
    app.save(job);
}

module.exports.changed = function (app, record, original) {
    if (record.collection().name === "media") {
        if (original && JSON.stringify(mediaInput(record)) === JSON.stringify(mediaInput(original))) return;
        enqueue(app, record, entryFor(app, record.getString("familyId"), record.getString("entryLocalId")),
            searchable(original));
        return;
    }
    if (original && JSON.stringify(entryInput(record)) === JSON.stringify(entryInput(original))) return;
    const associations = [record];
    if (original && (original.getString("localId") !== record.getString("localId")
            || original.getString("familyId") !== record.getString("familyId"))) associations.push(original);
    for (const entry of associations) {
        const currentEntry = entryFor(app, entry.getString("familyId"), entry.getString("localId"));
        let offset = 0;
        while (true) {
            const media = app.findRecordsByFilter("media",
                "entryLocalId={:local} && familyId={:family}", "id", 200, offset,
                { local: entry.getString("localId"), family: entry.getString("familyId") });
            for (const item of media) enqueue(app, item, currentEntry, false);
            if (media.length < 200) break;
            offset += media.length;
        }
    }
};

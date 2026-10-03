/// <reference path="../pb_data/types.d.ts" />
// Handlers are isolated programs; share pure helpers through a CommonJS module,
// not callback closures. https://pocketbase.io/docs/js-overview/#handlers-scope
onRecordAfterCreateSuccess((e) => {
    try {
        require(__hooks + "/semantic_jobs.js").changed(e.app, e.record, null);
    } catch (err) {
        // Derived work must never make a successful fact write look unsuccessful.
        console.log("[bubu-semantic] enqueue failed:", err);
    }
    e.next();
}, "media", "entries");

onRecordAfterUpdateSuccess((e) => {
    try {
        require(__hooks + "/semantic_jobs.js").changed(e.app, e.record, e.record.original());
    } catch (err) {
        console.log("[bubu-semantic] enqueue failed:", err);
    }
    e.next();
}, "media", "entries");

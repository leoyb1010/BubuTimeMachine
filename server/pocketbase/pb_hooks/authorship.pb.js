/// <reference path="../pb_data/types.d.ts" />
// 作者归属不可篡改：客户端 PATCH 时会把"当前用户"塞进 authorUserId（所有已发布版本都这样），
// 用规则拒绝会让家人互相编辑/删除全部 404。这里改为服务端钉住原值：原作者非空就恢复成原值，
// 原作者为空（历史记录）允许本次补齐。superuser（服务账号/后台）不受限。
const collectionsWithAuthor = [
    "entries", "media", "comments", "voicenotes", "milestones", "firsttimes",
    "voicememos", "healthrecords", "timecapsules", "vaccinerecords", "growthmeasurements",
];

onRecordUpdateRequest((e) => {
    try {
        if (!(e.auth && e.auth.isSuperuser())) {
            let original = "";
            try { original = e.record.original().getString("authorUserId"); } catch (_) { original = ""; }
            if (original && e.record.getString("authorUserId") !== original) {
                e.record.set("authorUserId", original);
            }
        }
    } catch (err) {
        console.log("[bubu-authorship] pin failed:", err);
    }
    e.next();
}, ...collectionsWithAuthor);

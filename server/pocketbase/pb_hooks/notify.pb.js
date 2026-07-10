/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 家庭推送 hook
// 有人新增一条记录 / 语音 / 里程碑时，向自托管 ntfy 广播一句，全家实时收到。
// 放在 PocketBase 的 pb_hooks/ 目录，随 PocketBase 启动生效。
//
// 配置（环境变量，无则用默认内网地址）：
//   BUBU_NTFY_URL   例 http://127.0.0.1:8095/bubu-family
//   BUBU_NTFY_TOKEN 例 tk_xxx（ntfy 授权 token，deny-all 模式必填）

function ntfyPublish(title, message, tag) {
    const url = $os.getenv("BUBU_NTFY_URL") || "http://127.0.0.1:8095/bubu-family";
    const token = $os.getenv("BUBU_NTFY_TOKEN");
    const headers = { "Title": title, "Tags": tag || "baby" };
    if (token) { headers["Authorization"] = "Bearer " + token; }
    try {
        $http.send({ url: url, method: "POST", body: message, headers: headers, timeout: 5 });
    } catch (err) {
        // 推送失败不影响记录本身
        console.log("[bubu-notify] ntfy publish failed:", err);
    }
}

function actorName(record) {
    // 记录里带 authorRole（爸爸/妈妈/…）用作署名，缺省「家人」
    try { return record.getString("authorRole") || "家人"; } catch (e) { return "家人"; }
}

onRecordAfterCreateSuccess((e) => {
    const r = e.record;
    // 软删/墓碑不推
    if (r.getBool("isDeleted")) { e.next(); return; }
    const who = actorName(r);
    const note = r.getString("note") || "记录了一个新瞬间";
    ntfyPublish("布布 · " + who, who + "：" + note, "baby,memo");
    e.next();
}, "entries");

onRecordAfterCreateSuccess((e) => {
    const r = e.record;
    ntfyPublish("布布 · 里程碑", "点亮了「" + (r.getString("title") || "新里程碑") + "」🌟", "star");
    e.next();
}, "milestones");

onRecordAfterCreateSuccess((e) => {
    const r = e.record;
    ntfyPublish("布布 · 成长之声", "新增了一段声音 🎤", "microphone");
    e.next();
}, "voicememos");

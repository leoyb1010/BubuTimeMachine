/// <reference path="../pb_data/types.d.ts" />
// 布布时光机 · 运维告警 hook
// ntfy 只发给维护者本人，不承载家庭动态，也不发送任何记忆正文。
// 配置：BUBU_NTFY_URL=http://127.0.0.1:8095/bubu-ops，BUBU_NTFY_TOKEN=tk_xxx

onRecordAfterUpdateSuccess((e) => {
    if (e.record.getString("state") === "dead_letter") {
        const url = $os.getenv("BUBU_NTFY_URL");
        if (url) {
            const token = $os.getenv("BUBU_NTFY_TOKEN");
            const headers = { "Title": "布布服务器 · 任务需处理", "Tags": "warning,computer" };
            if (token) { headers["Authorization"] = "Bearer " + token; }
            try {
                const kind = e.record.getString("kind") || "unknown";
                $http.send({
                    url: url,
                    method: "POST",
                    body: kind + " 任务连续失败，已进入死信队列。请查看 mini 日志。",
                    headers: headers,
                    timeout: 5,
                });
            } catch (err) {
                console.log("[bubu-ops] ntfy publish failed:", err);
            }
        }
    }
    e.next();
}, "automation_jobs");

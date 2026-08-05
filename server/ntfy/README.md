# 运维告警（自托管 ntfy）

只把备份过期、磁盘空间不足、服务异常、任务死信推给维护者本人。家庭动态继续由 App
同步后生成本地通知，不要求家人安装 ntfy，也不把记忆正文写进告警。

## 一、起服务（mini 上）

```bash
cd server/ntfy
cp .env.example .env            # 再改成实际 HTTPS 地址
docker compose up -d
# 建一个发布/订阅账号（deny-all 模式必须授权）
docker exec -it bubu-ntfy ntfy user add --role=admin bubu   # 设个密码
docker exec -it bubu-ntfy ntfy access bubu 'bubu-ops' rw  # 只授权运维话题
docker exec -it bubu-ntfy ntfy token add bubu                # 生成 token，记下来
```

## 二、接 PocketBase hook

1. `server/pocketbase/pb_hooks/notify.pb.js` 已随仓库提供，PocketBase 启动时自动加载该目录。
2. 给 PocketBase 进程加两个环境变量后重启：
   ```
   BUBU_NTFY_URL=http://127.0.0.1:8095/bubu-ops
   BUBU_NTFY_TOKEN=<上一步生成的 token>
   ```
   （在 `start_pocketbase.sh` 或 launchd plist 里 export）
3. 重启 PocketBase：`launchctl kickstart -k gui/$(id -u)/top.leoyuan.bubu.pocketbase`

## 三、维护者订阅

只在维护者手机安装 **ntfy** app：
- 添加服务器 `http://<mini的tailscale-ip>:8095`
- 用账号 `bubu` 登录，订阅话题 `bubu-ops`

## 安全
- 仅 Tailscale 内网可达；`deny-all` + token，未授权不能收发。
- 若经 Cloudflare Tunnel 暴露，只把 ntfy 绑定在 `127.0.0.1`，由 Tunnel 转发；不要直接开放 8095。
- 话题名不是安全边界，必须保留 `deny-all`、账号授权和 Tailscale/反向代理访问控制。
- 告警只含任务类型和健康状态，不含照片、文字、姓名、生日或记录正文。
- iOS 即时推送会经 `ntfy.sh → Firebase/APNS` 转发 poll request；只包含消息 id 与话题 URL 哈希，
  正文仍由 iPhone 从自托管服务器拉取。

## 验证
mini 上手动发一条，家人手机应立刻收到：
```bash
curl -H "Authorization: Bearer <token>" -H "Title: 测试" -d "布布运维告警通了" http://127.0.0.1:8095/bubu-ops
```

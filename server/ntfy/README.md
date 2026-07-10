# 家庭推送（自托管 ntfy）

「爸爸刚记录了 3 张照片」实时推到全家手机 / Apple Watch，全程跑在自己家 mini。

## 一、起服务（mini 上）

```bash
cd server/ntfy
docker compose up -d
# 建一个发布/订阅账号（deny-all 模式必须授权）
docker exec -it bubu-ntfy ntfy user add --role=admin bubu   # 设个密码
docker exec -it bubu-ntfy ntfy access bubu 'bubu-family' rw  # 授权收发 bubu-family 话题
docker exec -it bubu-ntfy ntfy token add bubu                # 生成 token，记下来
```

## 二、接 PocketBase hook

1. `server/pocketbase/pb_hooks/notify.pb.js` 已随仓库提供，PocketBase 启动时自动加载该目录。
2. 给 PocketBase 进程加两个环境变量后重启：
   ```
   BUBU_NTFY_URL=http://127.0.0.1:8095/bubu-family
   BUBU_NTFY_TOKEN=<上一步生成的 token>
   ```
   （在 `start_pocketbase.sh` 或 launchd plist 里 export）
3. 重启 PocketBase：`launchctl kickstart -k gui/$(id -u)/top.leoyuan.bubu.pocketbase`

## 三、家人订阅

每人手机装 **ntfy** app（App Store / Play）：
- 添加服务器 `http://<mini的tailscale-ip>:8095`
- 用账号 `bubu` 登录，订阅话题 `bubu-family`
- Apple Watch 会随 iPhone 通知自动转发，抬腕即见

## 安全
- 仅 Tailscale 内网可达；`deny-all` + token，未授权不能收发。
- 话题名 `bubu-family` 当口令，别设成公开可猜的词。
- hook 里对软删/墓碑记录不推送。

## 验证
mini 上手动发一条，家人手机应立刻收到：
```bash
curl -H "Authorization: Bearer <token>" -H "Title: 测试" -d "布布推送通了" http://127.0.0.1:8095/bubu-family
```

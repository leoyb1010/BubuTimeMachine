#!/usr/bin/env python3
"""把家庭影像档案里布布的照片按事件导入布布时光机。

设计见 docs/影像档案导入方案.md。

  # 1. 先看会导入什么(不联网、不写任何东西)
  python3 scripts/import_archive.py --archive "/Volumes/Leo-bubu/影像档案" --dry-run

  # 2. 确认无误后写入 PocketBase(先用 --limit 3 验证)
  python3 scripts/import_archive.py --archive ... --server http://mac-mini:8090 \
      --user leo@example.com --limit 3

安全:人物白名单与内容安全是两个正交维度。已确认是布布的照片里混着布布本人的
身份证(含有效号码),所以筛选必须同时满足"是布布"和"非敏感文档"两个条件。
"""

from __future__ import annotations

import argparse
import getpass
import json
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path

# 固定命名空间:localId 必须在多次运行间保持一致,否则重跑会产生重复记录
NAMESPACE = uuid.UUID("6f1b2c3d-0000-4000-8000-000000000001")

SESSION_GAP_HOURS = 3.0   # 同一天内间隔超过这么久就切成两件事
MIN_GROUP_SIZE = 5        # 少于这么多项的碎片不单独成条(见方案文档 3.2)
AUTHOR_ROLE = "档案导入"   # 固定值,便于日后筛选与整体回滚

# 只放行布布 + 排除一切证件/敏感内容。两个条件缺一不可。
SELECT_SQL = """
SELECT a.uuid, a.captured_at, a.kind, a.duration, a.width, a.height,
       a.primary_final_path, a.thumbnail_relative_path,
       COALESCE(NULLIF(a.area,''), NULLIF(a.city,''), '') AS place,
       a.latitude, a.longitude,
       COALESCE(i.auto_tags, '') AS auto_tags
FROM assets a
LEFT JOIN asset_content_index i ON i.uuid = a.uuid
WHERE a.daughter_status = '已确认'
  AND a.captured_at IS NOT NULL
  AND a.primary_final_path IS NOT NULL
  AND COALESCE(i.document_type, '') = ''
  AND COALESCE(i.sensitive, 0) = 0
ORDER BY a.captured_at
"""

# 自检:最终导入集里绝不允许出现证件或敏感项
ASSERT_SQL = """
SELECT COUNT(*) FROM (%s) t
JOIN asset_content_index i ON i.uuid = t.uuid
WHERE COALESCE(i.document_type,'') != '' OR COALESCE(i.sensitive,0) = 1
""" % SELECT_SQL.replace("ORDER BY a.captured_at", "")

EXCLUDED_SQL = """
SELECT COUNT(*) FROM assets a
LEFT JOIN asset_content_index i ON i.uuid = a.uuid
WHERE a.daughter_status = '已确认'
  AND (COALESCE(i.document_type,'') != '' OR COALESCE(i.sensitive,0) = 1)
"""


def parse_time(value: str) -> datetime | None:
    try:
        return datetime.strptime(str(value)[:19], "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return None


def day_part(hour: int) -> str:
    return "清晨" if hour < 8 else "上午" if hour < 12 else "下午" if hour < 18 else "晚上"


def load_assets(archive: Path) -> tuple[list[dict], int]:
    report_dir = archive / "99_影像检索与报告"
    connection = sqlite3.connect(report_dir / "影像数据库.sqlite")
    connection.row_factory = sqlite3.Row

    leaked = connection.execute(ASSERT_SQL).fetchone()[0]
    if leaked:
        raise SystemExit(f"安全自检失败:导入集里有 {leaked} 项证件/敏感内容,已中止。")
    excluded = connection.execute(EXCLUDED_SQL).fetchone()[0]

    assets = []
    for row in connection.execute(SELECT_SQL):
        moment = parse_time(row["captured_at"])
        if moment:
            assets.append({**dict(row), "moment": moment})
    connection.close()
    return assets, excluded


def group_sessions(assets: list[dict]) -> list[list[dict]]:
    """同一天内相邻两项间隔超过阈值就切开;跨天必切。"""
    if not assets:
        return []
    sessions, current = [], [assets[0]]
    for previous, item in zip(assets, assets[1:]):
        gap = (item["moment"] - previous["moment"]).total_seconds() / 3600
        if gap > SESSION_GAP_HOURS or item["moment"].date() != previous["moment"].date():
            sessions.append(current)
            current = []
        current.append(item)
    sessions.append(current)
    return sessions


def build_entry(group: list[dict]) -> dict:
    first = group[0]
    places = [item["place"] for item in group if item["place"]]
    place = Counter(places).most_common(1)[0][0] if places else ""
    located = next((item for item in group if item["latitude"] and item["longitude"]), None)
    moment = first["moment"]
    return {
        "localId": str(uuid.uuid5(NAMESPACE, f"archive-entry:{first['uuid']}")),
        "title": f"{moment:%Y年%m月%d日} {place or day_part(moment.hour)}",
        "happenedAt": moment.strftime("%Y-%m-%d %H:%M:%S"),
        "locationName": place,
        "latitude": located["latitude"] if located else None,
        "longitude": located["longitude"] if located else None,
        "authorRole": AUTHOR_ROLE,
        "note": "",
        "isArchived": False,
        "media": [build_media(item) for item in group],
    }


def build_media(item: dict) -> dict:
    is_video = item["kind"] == 1
    tags = [tag.strip() for tag in str(item["auto_tags"] or "").replace("，", ";").split(";") if tag.strip()]
    return {
        "localId": str(uuid.uuid5(NAMESPACE, f"archive-media:{item['uuid']}")),
        "uuid": item["uuid"],
        "mediaType": "video" if is_video else "photo",
        "sourcePath": item["primary_final_path"],
        "thumbnailPath": item["thumbnail_relative_path"],
        "durationSeconds": item["duration"] if is_video else None,
        "width": item["width"],
        "height": item["height"],
        "aiTags": tags[:8],
    }


def resolve_files(entry: dict, archive: Path, prefer_web: bool = True) -> None:
    """挑实际要上传的文件。

    视频用 H.264 副本(原片平均 317MB,会顶爆 PocketBase 500MB 上限);
    照片默认用 1600px 网页版(原片平均 4.7MB,网页版约 0.38MB)——App 首次同步
    要把每个媒体完整下到手机,体积直接决定同步时长。原片始终留在盘上不动。
    """
    report_dir = archive / "99_影像检索与报告"
    for media in entry["media"]:
        uid = media["uuid"]
        original = archive / media["sourcePath"]
        chosen, note = original, "原片"
        if media["mediaType"] == "video":
            transcoded = report_dir / "视频预览" / uid[:2] / f"{uid}.mp4"
            if transcoded.exists():
                chosen, note = transcoded, "H.264副本"
        elif prefer_web:
            web = report_dir / "网页版照片" / uid[:2] / f"{uid}.jpg"
            if web.exists():
                chosen, note = web, "1600px网页版"
        media["uploadPath"] = str(chosen)
        media["uploadKind"] = note
        media["uploadExists"] = chosen.exists()
        media["uploadBytes"] = chosen.stat().st_size if chosen.exists() else 0
        thumb = report_dir / media["thumbnailPath"] if media["thumbnailPath"] else None
        media["thumbnailFullPath"] = str(thumb) if thumb and thumb.exists() else ""


class PocketBase:
    def __init__(self, base: str, identity: str, password: str, superuser: bool = False) -> None:
        self.base = base.rstrip("/")
        self.superuser = superuser
        self.token = self._auth(identity, password)

    def _request(self, path: str, data: bytes | None = None, headers: dict | None = None) -> dict:
        request = urllib.request.Request(f"{self.base}{path}", data=data, headers=headers or {})
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))

    def _auth(self, identity: str, password: str) -> str:
        # 超级账号与普通家庭账号走不同的认证集合
        collection = "_superusers" if self.superuser else "users"
        body = json.dumps({"identity": identity, "password": password}).encode()
        result = self._request(f"/api/collections/{collection}/auth-with-password", body,
                               {"Content-Type": "application/json"})
        return result["token"]

    def exists(self, collection: str, local_id: str) -> bool:
        query = urllib.parse.quote(f'localId="{local_id}"')
        result = self._request(f"/api/collections/{collection}/records?filter={query}&perPage=1",
                               headers={"Authorization": self.token})
        return bool(result.get("items"))

    def create_json(self, collection: str, payload: dict) -> dict:
        body = json.dumps(payload).encode()
        return self._request(f"/api/collections/{collection}/records", body,
                             {"Content-Type": "application/json", "Authorization": self.token})

    def create_multipart(self, collection: str, fields: dict, files: dict) -> dict:
        boundary = f"----bubu{uuid.uuid4().hex}"
        parts = []
        for key, value in fields.items():
            if value is None:
                continue
            parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n".encode())
        for key, path in files.items():
            if not path:
                continue
            name = Path(path).name
            parts.append(
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"; filename=\"{name}\"\r\n"
                f"Content-Type: application/octet-stream\r\n\r\n".encode()
                + Path(path).read_bytes() + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())
        body = b"".join(parts)
        return self._request(f"/api/collections/{collection}/records", body, {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Authorization": self.token,
        })


def do_import(entries: list[dict], client: PocketBase) -> tuple[int, int, list[str]]:
    created_entries = created_media = 0
    failures: list[str] = []
    for index, entry in enumerate(entries, 1):
        try:
            if not client.exists("entries", entry["localId"]):
                client.create_json("entries", {
                    "localId": entry["localId"], "title": entry["title"], "note": entry["note"],
                    "happenedAt": entry["happenedAt"], "locationName": entry["locationName"],
                    "latitude": entry["latitude"], "longitude": entry["longitude"],
                    "authorRole": entry["authorRole"], "isArchived": False,
                    "clientUpdatedAt": entry["happenedAt"],
                })
                created_entries += 1
        except (urllib.error.URLError, KeyError, ValueError) as error:
            failures.append(f"entry {entry['title']}: {type(error).__name__}")
            continue
        for media in entry["media"]:
            if not media["uploadExists"]:
                failures.append(f"missing file: {media['sourcePath']}")
                continue
            try:
                if client.exists("media", media["localId"]):
                    continue
                client.create_multipart("media", {
                    "localId": media["localId"], "entryLocalId": entry["localId"],
                    "mediaType": media["mediaType"],
                    "durationSeconds": media["durationSeconds"], "width": media["width"],
                    "height": media["height"], "aiTags": json.dumps(media["aiTags"], ensure_ascii=False),
                    "clientUpdatedAt": entry["happenedAt"],
                }, {"file": media["uploadPath"], "thumbnail": media["thumbnailFullPath"]})
                created_media += 1
            except (urllib.error.URLError, OSError, ValueError) as error:
                failures.append(f"media {media['uuid']}: {type(error).__name__}")
        print(f"  [{index}/{len(entries)}] {entry['title']} — {len(entry['media'])} 项", flush=True)
    return created_entries, created_media, failures


def main() -> int:
    parser = argparse.ArgumentParser(description="把影像档案里布布的照片导入布布时光机")
    parser.add_argument("--archive", required=True, help="影像档案根目录")
    parser.add_argument("--dry-run", action="store_true", help="只输出清单,不联网不写入")
    parser.add_argument("--server", help="PocketBase 地址,如 http://mac-mini:8090")
    parser.add_argument("--user", help="PocketBase 账号")
    parser.add_argument("--superuser", action="store_true", help="按超级账号认证(_superusers 集合)")
    parser.add_argument("--password-file", help="从文件读密码,避免出现在命令行历史")
    parser.add_argument("--limit", type=int, help="只处理前 N 条(首次验证用)")
    parser.add_argument("--min-size", type=int, default=MIN_GROUP_SIZE, help=f"成条门槛,默认 {MIN_GROUP_SIZE}")
    parser.add_argument("--original-photos", action="store_true", help="照片上传原片而非1600px网页版(体积大14倍)")
    parser.add_argument("--manifest", default="/tmp/bubu_import_manifest.json", help="清单输出路径")
    args = parser.parse_args()

    archive = Path(args.archive)
    if not (archive / "99_影像检索与报告" / "影像数据库.sqlite").exists():
        raise SystemExit(f"找不到影像数据库:{archive}")

    assets, excluded = load_assets(archive)
    print(f"安全自检通过。可导入 {len(assets)} 项,已排除敏感项 {excluded} 条。")
    if excluded != 1:
        print(f"⚠️  排除数 {excluded} 与预期(1)不同,档案库识别结果可能有变化,建议先人工看一眼。")

    sessions = group_sessions(assets)
    kept = [s for s in sessions if len(s) >= args.min_size]
    entries = [build_entry(group) for group in kept]
    for entry in entries:
        resolve_files(entry, archive, prefer_web=not args.original_photos)
    if args.limit:
        entries = entries[:args.limit]

    kinds = Counter(m["uploadKind"] for e in entries for m in e["media"])
    covered = sum(len(e["media"]) for e in entries)
    missing = sum(1 for e in entries for m in e["media"] if not m["uploadExists"])
    upload_bytes = sum(m["uploadBytes"] for e in entries for m in e["media"])
    print(f"分组结果:{len(sessions)} 个事件 → 保留 {len(kept)} 条(门槛 ≥{args.min_size} 项)")
    print(f"本次将导入 {len(entries)} 条 / {covered} 个媒体 / {upload_bytes/1024**3:.2f} GB")
    print("  上传构成:" + "、".join(f"{k} {v}个" for k, v in kinds.most_common()))
    if missing:
        print(f"⚠️  有 {missing} 个文件在硬盘上找不到,会被跳过。")

    Path(args.manifest).write_text(json.dumps(entries, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"清单已写入 {args.manifest}")

    print("\n前 8 条预览:")
    for entry in entries[:8]:
        videos = sum(1 for m in entry["media"] if m["mediaType"] == "video")
        print(f"  {entry['title']:<30} {len(entry['media']):>3} 项(视频 {videos})")

    if args.dry_run:
        print("\n--dry-run:未写入任何数据。确认无误后去掉该参数并加上 --server/--user。")
        return 0
    if not args.server or not args.user:
        raise SystemExit("正式导入需要 --server 和 --user(或加 --dry-run 先看清单)")

    if args.password_file:
        password = Path(args.password_file).read_text(encoding="utf-8").strip()
    else:
        password = getpass.getpass(f"{args.user} 的 PocketBase 密码:")
    client = PocketBase(args.server, args.user, password, superuser=args.superuser)
    print(f"\n开始导入到 {args.server} …")
    n_entries, n_media, failures = do_import(entries, client)
    print(f"\n完成:新建 {n_entries} 条记录 / {n_media} 个媒体")
    if failures:
        print(f"失败 {len(failures)} 项:")
        for line in failures[:20]:
            print("  " + line)
    print("现在打开 App 触发一次同步即可看到。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

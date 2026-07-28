#!/usr/bin/env python3
"""为布布的照片生成 1600px 网页版，供导入 PocketBase 用（原片不动）。

App 首次同步要把每个媒体完整下到手机，原片平均 4.7MB、共 10GB，
在 30 秒一轮 + 每轮 8 个的旧逻辑下要跑几小时。1600px 版本压到约 8%，
iPhone 屏幕（1290px 宽）看不出差别，原片仍完整留在盘上。

  python3 make_web_photos.py <档案根目录>
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MAX_PIXEL = 1600
QUALITY = 78

SELECT = """
SELECT a.uuid, a.primary_final_path
FROM assets a
LEFT JOIN asset_content_index i ON i.uuid = a.uuid
WHERE a.daughter_status = '已确认'
  AND a.kind != 1
  AND a.primary_final_path IS NOT NULL
  AND COALESCE(i.document_type, '') = ''
  AND COALESCE(i.sensitive, 0) = 0
"""


def main() -> int:
    archive = Path(sys.argv[1])
    report = archive / "99_影像检索与报告"
    out_root = report / "网页版照片"
    rows = sqlite3.connect(report / "影像数据库.sqlite").execute(SELECT).fetchall()

    jobs = []
    for uuid, rel in rows:
        out = out_root / uuid[:2] / f"{uuid}.jpg"
        if out.exists() and out.stat().st_size > 0:
            continue
        jobs.append((archive / rel, out))
    print(f"待生成 {len(jobs)} 张（共 {len(rows)} 张布布照片）", flush=True)
    if not jobs:
        return 0

    failed = 0

    def convert(job: tuple[Path, Path]) -> bool:
        source, out = job
        out.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(QUALITY),
             "--resampleHeightWidthMax", str(MAX_PIXEL), str(source), "--out", str(out)],
            capture_output=True, timeout=120)
        if result.returncode != 0 or not out.exists() or out.stat().st_size == 0:
            out.unlink(missing_ok=True)
            return False
        return True

    with ThreadPoolExecutor(max_workers=8) as pool:
        for index, ok in enumerate(pool.map(convert, jobs), 1):
            failed += not ok
            if index % 300 == 0:
                print(f"  {index}/{len(jobs)}（失败 {failed}）", flush=True)

    total = sum(f.stat().st_size for f in out_root.rglob("*.jpg"))
    print(f"完成：成功 {len(jobs) - failed}，失败 {failed}，总计 {total / 1024**3:.2f} GB", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""把超过 PocketBase 上限的视频压到限额内,写回档案的 视频预览/ 目录。

PocketBase 的 media.file 字段上限 500MB(见 migrations/1700000000_init_collections.js)。
档案里已有的 H.264 副本按固定 3Mbps 转,半小时以上的长视频仍会超限;
另有少量本来就是 H.264 的原片没有副本、且体积过大。

按时长反推码率,保证成片落在预算内:
  码率 = 预算 / 时长,并限制在 [800kbps, 3Mbps] 之间

  python3 scripts/shrink_oversized_videos.py --manifest /tmp/bubu_import_manifest.json
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

BUDGET_MB = 420          # 留出余量,不贴着 500MB 上限
MIN_KBPS, MAX_KBPS = 800, 3000


def probe_duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, timeout=60)
    try:
        return float(result.stdout.strip())
    except ValueError:
        return 0.0


def shrink(source: Path, target: Path, duration: float) -> bool:
    budget_bits = BUDGET_MB * 8 * 1024  # kbit
    kbps = int(budget_bits / duration) if duration > 0 else MAX_KBPS
    kbps = max(MIN_KBPS, min(kbps, MAX_KBPS))
    audio_kbps = 96 if kbps < 1500 else 128
    temporary = target.with_suffix(".tmp.mp4")
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"  {source.name[:48]}  {duration:.0f}秒 → {kbps} kbps", flush=True)
    result = subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(source),
        "-map", "0:v:0", "-map", "0:a:0?",
        "-vf", "scale='min(1280,iw)':-2",
        "-c:v", "h264_videotoolbox", "-b:v", f"{kbps}k",
        "-c:a", "aac", "-b:a", f"{audio_kbps}k",
        "-movflags", "+faststart", str(temporary),
    ], capture_output=True, timeout=max(1800, duration * 6))
    if result.returncode != 0 or not temporary.exists() or temporary.stat().st_size == 0:
        temporary.unlink(missing_ok=True)
        return False
    temporary.replace(target)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="/tmp/bubu_import_manifest.json")
    parser.add_argument("--archive", default="/Volumes/Leo-bubu/影像档案")
    parser.add_argument("--limit-mb", type=int, default=500, help="PocketBase 上限")
    args = parser.parse_args()

    entries = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    preview_dir = Path(args.archive) / "99_影像检索与报告" / "视频预览"
    oversized = [m for e in entries for m in e["media"]
                 if m["mediaType"] == "video" and m["uploadBytes"] > args.limit_mb * 1024 ** 2]
    if not oversized:
        print("没有超限视频。")
        return 0

    print(f"发现 {len(oversized)} 个超过 {args.limit_mb}MB 的视频,目标 ≤{BUDGET_MB}MB:")
    ok = 0
    for media in oversized:
        source = Path(media["uploadPath"])
        target = preview_dir / media["uuid"][:2] / f"{media['uuid']}.mp4"
        duration = float(media.get("durationSeconds") or 0) or probe_duration(source)
        if shrink(source, target, duration):
            size = target.stat().st_size / 1024 ** 2
            flag = "✅" if size <= args.limit_mb else "❌仍超限"
            print(f"    → {size:.0f} MB {flag}")
            ok += size <= args.limit_mb
        else:
            print("    → 转码失败,跳过")
    print(f"\n完成 {ok}/{len(oversized)}。请重跑 import_archive.py --dry-run 确认。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

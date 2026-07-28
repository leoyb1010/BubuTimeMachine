#!/usr/bin/env python3
"""把布布某一批视频整理成"可直接拖进剪映"的精选文件夹。

半自动工作流的服务端一环:
  - 选一批(按年月 + 方向),只放行布布、排除敏感
  - 长视频(默认 >40 秒)自动抽出"最热闹"的一段(音频能量峰值 = 笑声/互动)
  - 短/中视频整条保留
  - 文件名带序号 + 日期 + 布布月龄 + 地点,拖进剪映后天然按时间排、字幕好写
  - 生成镜头清单 md

原片不动,只在工作区产出。之后你在剪映里导入 → 一键成片 → 调 → 导出。

  python3 curate_batch.py --months 2024-07,2024-08,2024-09 --orient portrait \
      --name 2024Q3_布布第一个夏天
"""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import subprocess
import tempfile
import wave
from datetime import date, datetime
from pathlib import Path

ARCHIVE = Path("/Volumes/Leo-bubu/影像档案")
REPORT = ARCHIVE / "99_影像检索与报告"
DB = REPORT / "影像数据库.sqlite"
WORKSPACE = Path("/Volumes/Leo-bubu/视频工作区/01_高光片段")
BIRTHDAY = date(2024, 5, 22)   # 布布出生日(取自医院那条记录,可用 --birthday 覆盖)

LONG_SECONDS = 40.0            # 超过这么长就抽高光
HIGHLIGHT_SECONDS = 12.0       # 抽出来的高光段时长
SKIP_HEAD = 2.0               # 跳过开头手忙脚乱的秒数


def age_label(captured: date, birthday: date) -> str:
    months = (captured.year - birthday.year) * 12 + captured.month - birthday.month
    if captured.day < birthday.day:
        months -= 1
    anchor_month = birthday.month + months
    anchor_year = birthday.year + (anchor_month - 1) // 12
    anchor = date(anchor_year, (anchor_month - 1) % 12 + 1, min(birthday.day, 28))
    days = (captured - anchor).days
    if months <= 0:
        return f"布布{max(days, (captured - birthday).days)}天"
    return f"布布{months}个月" + (f"{days}天" if days else "")


def loudest_window(source: Path, total: float) -> float:
    """返回音频能量最高的一段的起点(秒)。纯 stdlib,不依赖 numpy。"""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as handle:
        wav_path = Path(handle.name)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(source),
             "-ac", "1", "-ar", "8000", "-vn", str(wav_path)],
            capture_output=True, timeout=120)
        if not wav_path.exists() or wav_path.stat().st_size == 0:
            return SKIP_HEAD
        with wave.open(str(wav_path), "rb") as wav:
            rate = wav.getframerate()
            frames = wav.readframes(wav.getnframes())
        import array
        samples = array.array("h")
        samples.frombytes(frames)
        # 每秒的能量(平方和)
        per_sec = []
        for start in range(0, len(samples), rate):
            chunk = samples[start:start + rate]
            per_sec.append(sum(v * v for v in chunk) / max(len(chunk), 1))
        win = int(HIGHLIGHT_SECONDS)
        skip = int(SKIP_HEAD)
        best_start, best_energy = skip, -1.0
        for start in range(skip, max(skip + 1, len(per_sec) - win)):
            energy = sum(per_sec[start:start + win])
            if energy > best_energy:
                best_energy, best_start = energy, start
        # 不越界
        return float(min(best_start, max(0.0, total - HIGHLIGHT_SECONDS)))
    finally:
        wav_path.unlink(missing_ok=True)


def resolve_source(uuid: str, rel: str) -> Path:
    """视频优先用 H.264 副本(剪映友好),没有再退原片。"""
    copy = REPORT / "视频预览" / uuid[:2] / f"{uuid}.mp4"
    return copy if copy.exists() else ARCHIVE / rel


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--months", required=True, help="逗号分隔,如 2024-07,2024-08,2024-09")
    parser.add_argument("--orient", choices=["portrait", "landscape", "all"], default="all")
    parser.add_argument("--name", required=True, help="批次名(输出文件夹名)")
    parser.add_argument("--birthday", default="2024-05-22")
    parser.add_argument("--long-seconds", type=float, default=LONG_SECONDS)
    args = parser.parse_args()

    birthday = datetime.strptime(args.birthday, "%Y-%m-%d").date()
    months = tuple(m.strip() for m in args.months.split(","))
    orient_sql = {"portrait": "AND a.height > a.width",
                  "landscape": "AND a.width >= a.height", "all": ""}[args.orient]
    placeholders = ",".join("?" * len(months))

    connection = sqlite3.connect(DB)
    rows = connection.execute(f"""
        SELECT a.uuid, a.captured_at, a.duration, a.primary_final_path,
               COALESCE(NULLIF(a.area,''), NULLIF(a.city,''), '') AS place
        FROM assets a
        LEFT JOIN asset_content_index i ON i.uuid = a.uuid
        WHERE a.daughter_status = '已确认' AND a.kind = 1
          AND substr(a.captured_at, 1, 7) IN ({placeholders})
          AND COALESCE(i.document_type, '') = '' AND COALESCE(i.sensitive, 0) = 0
          {orient_sql}
        ORDER BY a.captured_at
    """, months).fetchall()
    connection.close()

    out_dir = WORKSPACE / args.name
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"批次「{args.name}」: {len(rows)} 条视频 → {out_dir}", flush=True)

    shot_list = [f"# {args.name}\n", f"> 布布出生 {birthday}｜共 {len(rows)} 条\n"]
    made = 0
    for index, (uuid, captured_at, duration, rel, place) in enumerate(rows, 1):
        captured = datetime.strptime(captured_at[:19], "%Y-%m-%d %H:%M:%S")
        age = age_label(captured.date(), birthday)
        source = resolve_source(uuid, rel)
        if not source.exists():
            print(f"  [{index}] 缺文件,跳过 {uuid}", flush=True)
            continue
        place_tag = place or "未知地点"
        stem = f"{index:02d}_{captured:%Y-%m-%d}_{age}_{place_tag}"
        target = out_dir / f"{stem}.mp4"

        if duration and duration > args.long_seconds:
            start = loudest_window(source, float(duration))
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}",
                 "-i", str(source), "-t", f"{HIGHLIGHT_SECONDS:.2f}",
                 "-vf", "fade=t=in:st=0:d=0.3,fade=t=out:st=%.2f:d=0.3" % (HIGHLIGHT_SECONDS - 0.3),
                 "-c:v", "h264_videotoolbox", "-b:v", "6M",
                 "-af", "afade=t=in:st=0:d=0.3,afade=t=out:st=%.2f:d=0.3" % (HIGHLIGHT_SECONDS - 0.3),
                 "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(target)],
                capture_output=True, timeout=180)
            note = f"高光段(原 {duration:.0f}秒,取 {start:.0f}s 起 {HIGHLIGHT_SECONDS:.0f}秒)"
        else:
            shutil.copy2(source, target)
            note = f"整条 {duration:.0f}秒"

        if target.exists() and target.stat().st_size > 0:
            made += 1
            shot_list.append(f"{index:02d}. **{captured:%m-%d}** {age}｜{place_tag}｜{note}")
        else:
            print(f"  [{index}] 生成失败 {stem}", flush=True)

    (out_dir / "镜头清单.md").write_text("\n".join(shot_list) + "\n", encoding="utf-8")
    total = sum(f.stat().st_size for f in out_dir.glob("*.mp4"))
    print(f"完成: {made}/{len(rows)} 条,共 {total/1024**2:.0f} MB", flush=True)
    print(f"镜头清单: {out_dir / '镜头清单.md'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

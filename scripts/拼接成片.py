#!/usr/bin/env python3
"""把整理好的一批高光片段拼成一版可直接看的粗剪。

- 开头标题卡
- 每条片段前 2.5 秒叠一张下方字幕卡(日期 · 布布月龄 · 地点),PIL 渲染中文
- 每段 0.25 秒淡入淡出(视频+音频),硬接更顺
- 保留布布自己的声音(咿呀笑闹),不加音乐——音乐留给剪映或后续
产出到 02_成片/<批次名>_粗剪.mp4,你在剪映里精修即可。

  python3 assemble_film.py --batch 2024Q3_布布第一个夏天 --title "布布的第一个夏天" --subtitle "2024 · 出生后第一个夏天"
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WORKSPACE = Path("/Volumes/Leo-bubu/视频工作区")
OUT_DIR = WORKSPACE / "02_成片"
FONT_BOLD = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_REG = "/System/Library/Fonts/STHeiti Light.ttc"
W, H = 1080, 1920
FPS = 30
CARD_SECONDS = 2.5
FADE = 0.25


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def lower_third_png(text_main: str, text_sub: str, out: Path) -> None:
    """透明底的下方字幕卡,叠在视频上。"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    f_main = font(FONT_BOLD, 56)
    f_sub = font(FONT_REG, 38)
    y = H - 300
    # 半透明底条
    draw.rectangle([0, y - 30, W, y + 150], fill=(0, 0, 0, 110))
    for text, f, dy, color in ((text_main, f_main, 0, (255, 255, 255, 255)),
                               (text_sub, f_sub, 78, (235, 220, 190, 255))):
        if not text:
            continue
        w = draw.textbbox((0, 0), text, font=f)[2]
        draw.text(((W - w) / 2, y + dy), text, font=f, fill=color)
    img.save(out)


def title_card_png(title: str, subtitle: str, out: Path) -> None:
    img = Image.new("RGB", (W, H), (18, 18, 20))
    draw = ImageDraw.Draw(img)
    f_title = font(FONT_BOLD, 96)
    f_sub = font(FONT_REG, 46)
    tw = draw.textbbox((0, 0), title, font=f_title)[2]
    draw.text(((W - tw) / 2, H / 2 - 120), title, font=f_title, fill=(245, 240, 232))
    if subtitle:
        sw = draw.textbbox((0, 0), subtitle, font=f_sub)[2]
        draw.text(((W - sw) / 2, H / 2 + 20), subtitle, font=f_sub, fill=(200, 180, 140))
    img.save(out)


def parse_name(path: Path) -> tuple[str, str, str]:
    # 01_2024-07-10_布布1个月18天_地点.mp4
    parts = path.stem.split("_")
    date = parts[1] if len(parts) > 1 else ""
    age = parts[2] if len(parts) > 2 else ""
    place = parts[3] if len(parts) > 3 else ""
    return date, age, place


def run(cmd: list[str], timeout: int = 300) -> bool:
    result = subprocess.run(cmd, capture_output=True, timeout=timeout)
    if result.returncode != 0:
        print("  ffmpeg 失败:", result.stderr.decode("utf-8", "ignore")[-200:], flush=True)
    return result.returncode == 0


def make_segment(src: Path, caption_png: Path, out: Path) -> bool:
    """叠字幕卡(前 CARD_SECONDS 秒)+ 淡入淡出 + 统一参数。"""
    vf = (f"scale={W}:{H}:force_original_aspect_ratio=decrease,"
          f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=black,fps={FPS},format=yuv420p[v];"
          f"[v][1:v]overlay=0:0:enable='lt(t,{CARD_SECONDS})'[vo];"
          f"[vo]fade=t=in:st=0:d={FADE}[vf]")
    # 时长用于尾部淡出
    dur = probe_duration(src)
    vf = vf.replace("[vf]", f",fade=t=out:st={max(0.0, dur - FADE):.2f}:d={FADE}[vf]")
    return run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-i", str(caption_png),
                "-filter_complex", vf, "-map", "[vf]", "-map", "0:a?",
                "-af", f"afade=t=in:st=0:d={FADE},afade=t=out:st={max(0.0, dur - FADE):.2f}:d={FADE}",
                "-c:v", "h264_videotoolbox", "-b:v", "6M", "-c:a", "aac", "-b:a", "128k",
                "-r", str(FPS), str(out)])


def make_title_clip(png: Path, out: Path) -> bool:
    return run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", f"{CARD_SECONDS}",
                "-i", str(png), "-f", "lavfi", "-t", f"{CARD_SECONDS}", "-i", "anullsrc=r=44100:cl=stereo",
                "-vf", f"fps={FPS},format=yuv420p,fade=t=in:st=0:d=0.4,fade=t=out:st={CARD_SECONDS-0.4}:d=0.4",
                "-c:v", "h264_videotoolbox", "-b:v", "6M", "-c:a", "aac", "-b:a", "128k",
                "-r", str(FPS), str(out)])


def probe_duration(path: Path) -> float:
    result = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                             "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    try:
        return float(result.stdout.strip())
    except ValueError:
        return 0.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    args = parser.parse_args()

    batch_dir = WORKSPACE / "01_高光片段" / args.batch
    clips = sorted(batch_dir.glob("*.mp4"))
    if not clips:
        raise SystemExit(f"没找到片段: {batch_dir}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp())
    print(f"拼接「{args.batch}」: {len(clips)} 段", flush=True)

    segments = []
    # 标题卡
    tcard = work / "title.png"
    title_card_png(args.title, args.subtitle, tcard)
    tclip = work / "00_title.mp4"
    if make_title_clip(tcard, tclip):
        segments.append(tclip)

    for index, clip in enumerate(clips, 1):
        date, age, place = parse_name(clip)
        cap = work / f"cap_{index:02d}.png"
        lower_third_png(f"{age}", f"{date}  ·  {place}", cap)
        seg = work / f"seg_{index:02d}.mp4"
        if make_segment(clip, cap, seg):
            segments.append(seg)
        if index % 10 == 0:
            print(f"  {index}/{len(clips)}", flush=True)

    # concat
    listfile = work / "list.txt"
    listfile.write_text("".join(f"file '{s}'\n" for s in segments), encoding="utf-8")
    out = OUT_DIR / f"{args.batch}_粗剪.mp4"
    ok = run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
              "-i", str(listfile), "-c", "copy", str(out)], timeout=600)
    if not ok or not out.exists():
        # copy 失败(参数不齐)则重编码兜底
        run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
             "-i", str(listfile), "-c:v", "h264_videotoolbox", "-b:v", "6M",
             "-c:a", "aac", "-r", str(FPS), str(out)], timeout=900)
    dur = probe_duration(out)
    size = out.stat().st_size / 1024**2 if out.exists() else 0
    print(f"✅ 成片: {out}", flush=True)
    print(f"   时长 {dur:.0f} 秒 / {size:.0f} MB / {len(segments)} 段(含标题卡)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

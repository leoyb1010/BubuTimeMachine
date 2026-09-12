"""把 Pillow 解不开的媒体（HEIC 原片、无缩略图的视频）转成 JPEG。

macOS 自带 sips 转 HEIC/HEIF；视频用 ffmpeg 抽帧，退回 qlmanage 缩略图。
launchd 的 PATH 只有系统目录，Homebrew 工具按绝对路径兜底。
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional


def _pil_can_open(path: Path) -> bool:
    try:
        from PIL import Image
    except ImportError:
        return True  # 交给 encoder 自己报"未安装 Pillow"
    try:
        with Image.open(path) as image:
            image.verify()
        return True
    except Exception:  # noqa: BLE001
        return False


def _tool(name: str) -> Optional[str]:
    """launchd 的 PATH 只有系统目录；Homebrew 的 ffmpeg 要按绝对路径兜底。"""
    found = shutil.which(name)
    if found:
        return found
    for candidate in ("/opt/homebrew/bin/" + name, "/usr/local/bin/" + name, "/usr/bin/" + name):
        if os.path.exists(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def _run_quiet(cmd: list, timeout: int = 60) -> bool:
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout, check=False).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def prepare_visual_for_encoding(path: Path, media_type: str, force: bool = False) -> Path:
    """把下载下来的媒体转成 Pillow 一定能解的 JPEG。已可解则原样返回。

    照片：sips（macOS 自带）转 HEIC/HEIF/AVIF；视频：ffmpeg 抽 1 秒处一帧，退回 qlmanage 缩略图。
    都失败时抛 RuntimeError，让任务带明确原因失败，而不是 Pillow 的 UnidentifiedImageError。
    """
    if not force and _pil_can_open(path):
        return path
    output = path.with_name(path.name + ".decoded.jpg")
    if media_type == "video":
        ffmpeg = _tool("ffmpeg")
        if ffmpeg:
            cmd = [ffmpeg, "-y", "-loglevel", "error", "-ss", "1", "-i", str(path),
                   "-frames:v", "1", "-q:v", "3", str(output)]
            if _run_quiet(cmd) and output.exists() and output.stat().st_size > 0 and _pil_can_open(output):
                return output
        qlmanage = _tool("qlmanage")
        if qlmanage:
            thumb_dir = path.parent / "ql"
            thumb_dir.mkdir(exist_ok=True)
            if _run_quiet([qlmanage, "-t", "-s", "1024", "-o", str(thumb_dir), str(path)], timeout=30):
                produced = sorted(thumb_dir.glob("*.png"))
                if produced and _pil_can_open(produced[0]):
                    return produced[0]
        raise RuntimeError("视频没有可用缩略图且无法抽帧（需要 ffmpeg 或 qlmanage）")
    sips = _tool("sips")
    if sips:
        if _run_quiet([sips, "-s", "format", "jpeg", str(path), "--out", str(output)]) \
                and output.exists() and _pil_can_open(output):
            return output
    raise RuntimeError("图片格式无法解码（HEIC/HEIF 需要 macOS sips 或 pillow-heif）")


# semantic_worker 通过 `import semantic_worker; semantic_worker._tool` 之类的名字做测试替身，保留可见性。
token_free_reexports = (_pil_can_open, _tool, _run_quiet)

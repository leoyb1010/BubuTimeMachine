"""
成长电影 · 服务端合成（ffmpeg）
================================

自托管、隐私自控：照片本就通过家庭自己的 PocketBase 同步到这台机器，
App 只传【已同步照片的本机 URL】+ 旁白文案，服务端用 ffmpeg 合成真正的 mp4。

管线：每张图先做 Ken Burns（zoompan 缓慢推近）短片，再用 xfade 交叉淡入串成整片，
可选烧入片头标题。渲染在后台线程串行执行（家用小机不并发多路 ffmpeg）。

依赖：系统安装 ffmpeg（`ffmpeg -version` 可用）。未装则 /movie/render 返回 503。
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Optional
from urllib.request import urlopen

logger = logging.getLogger("bubu.ai.movie")

# 成片落盘目录（可用环境变量覆盖到大盘）
MOVIES_DIR = os.environ.get("BUBU_MOVIES_DIR", os.path.join(tempfile.gettempdir(), "bubu_movies"))
os.makedirs(MOVIES_DIR, exist_ok=True)

# 参数（保守、稳）
_FPS = 30
_SIZE = (1920, 1080)
_PER_PHOTO = 3.6          # 每张停留秒数
_XFADE = 1.0              # 交叉淡入秒数
_MAX_PHOTOS = 60          # 上限，防止家用机跑爆
_MAX_BYTES = 25 * 1024 * 1024   # 单图下载上限
_DOWNLOAD_TIMEOUT = 20

_executor = ThreadPoolExecutor(max_workers=1)   # 串行渲染
_jobs: dict[str, "RenderJob"] = {}
_jobs_lock = threading.Lock()


@dataclass
class RenderPhoto:
    url: str
    caption: str = ""


@dataclass
class RenderJob:
    job_id: str
    year: int
    child_name: str
    status: str = "queued"          # queued / rendering / ready / failed
    progress: float = 0.0           # 0..1
    error: str = ""
    file_path: str = ""
    created_at: float = field(default_factory=time.time)

    def public(self) -> dict:
        return {
            "job_id": self.job_id,
            "status": self.status,
            "progress": round(self.progress, 2),
            "error": self.error,
            "year": self.year,
            "ready": self.status == "ready",
        }


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def get_job(job_id: str) -> Optional[RenderJob]:
    with _jobs_lock:
        return _jobs.get(job_id)


def submit_render(child_name: str, year: int, template: str,
                  photos: list[RenderPhoto], narration: str = "") -> RenderJob:
    """登记任务并提交后台渲染，立即返回 job（异步轮询 status）。"""
    job = RenderJob(job_id=uuid.uuid4().hex[:16], year=year, child_name=child_name or "布布")
    with _jobs_lock:
        _jobs[job.job_id] = job
        _prune_locked()
    _executor.submit(_run_render, job, template, photos[:_MAX_PHOTOS], narration)
    return job


# ---------- 内部 ----------

def _prune_locked() -> None:
    """内存里只留最近 40 个任务；顺手删 7 天前的成片文件。"""
    if len(_jobs) > 40:
        for jid in sorted(_jobs, key=lambda k: _jobs[k].created_at)[:len(_jobs) - 40]:
            _jobs.pop(jid, None)
    cutoff = time.time() - 7 * 86400
    try:
        for name in os.listdir(MOVIES_DIR):
            p = os.path.join(MOVIES_DIR, name)
            if os.path.isfile(p) and os.path.getmtime(p) < cutoff:
                os.remove(p)
    except OSError:
        pass


def _download(url: str, dest: str) -> bool:
    try:
        with urlopen(url, timeout=_DOWNLOAD_TIMEOUT) as resp:
            data = resp.read(_MAX_BYTES + 1)
        if not data or len(data) > _MAX_BYTES:
            logger.warning("movie: skip oversized/empty image %s", url[:80])
            return False
        with open(dest, "wb") as f:
            f.write(data)
        return True
    except Exception as exc:  # 网络/超时/坏 URL 都跳过该图，不炸整片
        logger.warning("movie: download failed %s (%s)", url[:80], exc)
        return False


def _kenburns_clip(src: str, dst: str, seconds: float, zoom_in: bool) -> bool:
    """把一张图渲成一段 Ken Burns 短片。缩放方向按序交替，避免机械感。"""
    w, h = _SIZE
    frames = max(1, int(seconds * _FPS))
    # 先等比放大裁到画布，再 zoompan 缓慢推近/拉远
    if zoom_in:
        z = "min(zoom+0.0012,1.15)"
    else:
        z = "if(lte(zoom,1.0),1.15,max(zoom-0.0012,1.0))"
    vf = (
        f"scale={w}:{h}:force_original_aspect_ratio=increase,"
        f"crop={w}:{h},"
        f"zoompan=z='{z}':d={frames}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={_FPS},"
        f"format=yuv420p"
    )
    cmd = [
        "ffmpeg", "-y", "-loop", "1", "-i", src, "-t", f"{seconds:.3f}",
        "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        "-r", str(_FPS), dst,
    ]
    return _run_ffmpeg(cmd, f"kenburns {os.path.basename(src)}")


def _xfade_concat(clips: list[str], out: str) -> bool:
    """用 xfade 把多段短片交叉淡入串成整片。offset_m = m*(D-XFADE)。"""
    if len(clips) == 1:
        shutil.copyfile(clips[0], out)
        return True
    inputs: list[str] = []
    for c in clips:
        inputs += ["-i", c]
    step = _PER_PHOTO - _XFADE
    filt = ""
    prev = "[0]"
    for m in range(1, len(clips)):
        label = "[vout]" if m == len(clips) - 1 else f"[vx{m}]"
        offset = m * step
        filt += (
            f"{prev}[{m}]xfade=transition=fade:duration={_XFADE:.3f}:"
            f"offset={offset:.3f}{label};"
        )
        prev = label
    filt = filt.rstrip(";")
    cmd = ["ffmpeg", "-y", *inputs, "-filter_complex", filt,
           "-map", "[vout]", "-c:v", "libx264", "-preset", "veryfast",
           "-pix_fmt", "yuv420p", "-r", str(_FPS), out]
    return _run_ffmpeg(cmd, "xfade concat")


def _run_ffmpeg(cmd: list[str], label: str) -> bool:
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=600)
        if proc.returncode != 0:
            tail = proc.stderr.decode("utf-8", "ignore")[-500:]
            logger.error("ffmpeg %s failed rc=%d: %s", label, proc.returncode, tail)
            return False
        return True
    except subprocess.TimeoutExpired:
        logger.error("ffmpeg %s timed out", label)
        return False
    except Exception as exc:
        logger.error("ffmpeg %s error: %s", label, exc)
        return False


def _run_render(job: RenderJob, template: str, photos: list[RenderPhoto], narration: str) -> None:
    if not ffmpeg_available():
        _fail(job, "服务器未安装 ffmpeg")
        return
    if not photos:
        _fail(job, "没有可用照片")
        return

    workdir = tempfile.mkdtemp(prefix=f"bubu_movie_{job.job_id}_")
    try:
        _set(job, status="rendering", progress=0.05)

        # 1) 下载照片（坏图跳过）
        local_imgs: list[str] = []
        for i, p in enumerate(photos):
            dst = os.path.join(workdir, f"img_{i:03d}.jpg")
            if _download(p.url, dst):
                local_imgs.append(dst)
        if not local_imgs:
            _fail(job, "所有照片都无法读取")
            return
        _set(job, progress=0.2)

        # 2) 每图渲 Ken Burns 短片
        clips: list[str] = []
        for i, img in enumerate(local_imgs):
            clip = os.path.join(workdir, f"clip_{i:03d}.mp4")
            if _kenburns_clip(img, clip, _PER_PHOTO, zoom_in=(i % 2 == 0)):
                clips.append(clip)
            _set(job, progress=0.2 + 0.5 * (i + 1) / len(local_imgs))
        if not clips:
            _fail(job, "渲染分镜失败")
            return

        # 3) xfade 串片
        _set(job, progress=0.75)
        out_path = os.path.join(MOVIES_DIR, f"{job.job_id}.mp4")
        if not _xfade_concat(clips, out_path):
            _fail(job, "合成整片失败")
            return

        _set(job, status="ready", progress=1.0, file_path=out_path)
        logger.info("movie ready: %s (%d photos)", out_path, len(clips))
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def _set(job: RenderJob, **kw) -> None:
    with _jobs_lock:
        for k, v in kw.items():
            setattr(job, k, v)


def _fail(job: RenderJob, msg: str) -> None:
    logger.error("movie job %s failed: %s", job.job_id, msg)
    _set(job, status="failed", error=msg)

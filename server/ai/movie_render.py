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

import ipaddress
import logging
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Optional
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener

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


# ---------- 下载 URL 白名单（SSRF/LFI 防护）----------
# 背景：/movie/render 的 photo.url 完全来自客户端。若直接 urlopen(url)，持 key 者可传
# file:///etc/passwd 读本地文件，或 http://127.0.0.1:8090 / http://169.254.169.254
# 探测内网与云元数据，并把结果渲进 mp4 外泄。故此处强制：只允许下载指向【已配置的
# 自托管 PocketBase 主机】的 http/https 图片，其余一律拒绝（fail-closed）。

# 未配置时的默认白名单：标准单机自托管（AI 与 PocketBase 同机）开箱即用。
# 仍只放行本机 PB 的这个端口，file:// / 外网 / 私网其它 IP / 本机其它端口一律照拦。
# Tailscale 或 PB 独立机部署时，用 PB_BASE_URL 覆盖成实际地址。
_DEFAULT_ALLOWED_HOSTS = {"127.0.0.1:8090", "localhost:8090"}


def _load_allowed_hosts() -> set:
    """从环境变量读取 PocketBase 白名单主机（host 或 host:port，逗号可分隔多个）。
    优先 PB_BASE_URL（形如 http://127.0.0.1:8090，含端口最精确），退回 BUBU_PB_HOST。
    未配置时退回本机 PB 默认白名单（单机部署开箱即用），而非拒绝一切。"""
    raw = os.environ.get("PB_BASE_URL", "").strip() or os.environ.get("BUBU_PB_HOST", "").strip()
    allowed: set = set()
    if not raw:
        return set(_DEFAULT_ALLOWED_HOSTS)
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        # 允许直接给 host / host:port，也允许给完整 URL；统一补 scheme 好让 urlsplit 解析
        if "://" not in item:
            item = "//" + item
        try:
            p = urlsplit(item)
        except ValueError:
            continue
        host = (p.hostname or "").lower()
        if not host:
            continue
        try:
            port = p.port
        except ValueError:
            port = None
        if port:
            allowed.add(f"{host}:{port}")   # 精确到端口：挡住同机其它端口(redis/后台)的横向探测
        else:
            allowed.add(host)               # 未给端口则按主机放行
    return allowed


_ALLOWED_HOSTS = _load_allowed_hosts()


def _ip_is_dangerous(ip) -> bool:
    """私有/保留网段判断：环回、私网、链路本地(含 169.254 云元数据)、保留、组播、未指定。"""
    return (ip.is_private or ip.is_loopback or ip.is_link_local
            or ip.is_reserved or ip.is_multicast or ip.is_unspecified)


def _is_allowed_url(url: str) -> bool:
    """校验单个下载 URL 是否安全放行。任何不满足项都返回 False（跳过该图，不炸整片）。
    规则：
      1) scheme 仅 http/https —— 挡 file://、ftp://、gopher://、data: 等本地文件/协议走私。
      2) host 必须精确命中白名单（host:port 或裸 host）；空白名单 = 全拒。
      3) host 若为 DNS 名，解析后不得落在私有/保留网段（防 DNS 重绑定探内网/元数据）；
         白名单里显式配置的 IP 字面量（如自托管 PB 的 127.0.0.1）按预期例外放行。"""
    try:
        p = urlsplit(url)
    except ValueError:
        return False
    scheme = (p.scheme or "").lower()
    if scheme not in ("http", "https"):
        logger.warning("movie: reject url (scheme=%s) %s", scheme, url[:80])
        return False
    host = (p.hostname or "").lower()
    if not host:
        logger.warning("movie: reject url (no host) %s", url[:80])
        return False
    try:
        port = p.port or (443 if scheme == "https" else 80)
    except ValueError:
        logger.warning("movie: reject url (bad port) %s", url[:80])
        return False
    if f"{host}:{port}" not in _ALLOWED_HOSTS and host not in _ALLOWED_HOSTS:
        logger.warning("movie: reject non-whitelisted host %s:%s", host, port)
        return False
    # host 是否本身就是 IP 字面量（自托管 PB 常配 127.0.0.1 / 192.168.x）
    try:
        host_ip = ipaddress.ip_address(host)
    except ValueError:
        host_ip = None
    # 解析所有地址，逐个校验私网；防止白名单 DNS 名被重绑定到内网/元数据地址
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except OSError as exc:
        logger.warning("movie: dns resolve failed %s (%s)", host, exc)
        return False
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            return False
        if _ip_is_dangerous(ip):
            # 仅当白名单填的就是这个 IP 字面量本身，才放行（如显式配置的 loopback PB）
            if host_ip is not None and host_ip == ip:
                continue
            logger.warning("movie: reject private/reserved target %s -> %s", host, addr)
            return False
    return True


class _ValidatingRedirectHandler(HTTPRedirectHandler):
    """urllib 默认会跟随 3xx 重定向，绕过初始 host 校验。这里对每个重定向目标重新过一遍
    _is_allowed_url —— 拦住「白名单图片 302 到 file:// 或 169.254.169.254」这类绕过。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _is_allowed_url(newurl):
            raise URLError("blocked redirect to disallowed url: %s" % (newurl[:80],))
        return super().redirect_request(req, fp, code, msg, headers, newurl)


# 复用一个装了校验重定向处理器的 opener（替代裸 urlopen）
_opener = build_opener(_ValidatingRedirectHandler)


def _resolve_ffmpeg() -> str:
    """launchd 下 PATH 极简，不含 /opt/homebrew/bin，shutil.which 会找不到；
    显式回退到 Homebrew 常见安装路径。"""
    found = shutil.which("ffmpeg")
    if found:
        return found
    for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
        if os.path.exists(p):
            return p
    return "ffmpeg"


_FFMPEG = _resolve_ffmpeg()


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
    return _FFMPEG != "ffmpeg" or shutil.which("ffmpeg") is not None


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
    # 下载前先过 SSRF/LFI 白名单校验，非法直接跳过该图（与坏 URL 一样不炸整片）
    if not _is_allowed_url(url):
        return False
    try:
        with _opener.open(url, timeout=_DOWNLOAD_TIMEOUT) as resp:
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
        _FFMPEG, "-y", "-loop", "1", "-i", src, "-t", f"{seconds:.3f}",
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
    cmd = [_FFMPEG, "-y", *inputs, "-filter_complex", filt,
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

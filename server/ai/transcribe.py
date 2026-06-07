"""
语音转写（可选模块）· faster-whisper
默认懒加载、CPU、small 模型；首启会下载权重。
未安装 faster-whisper 时，main.py 的 /transcribe 会优雅降级为 501。
"""
from __future__ import annotations

import os
import tempfile
from functools import lru_cache


@lru_cache(maxsize=1)
def _model():
    from faster_whisper import WhisperModel  # 延迟导入
    size = os.environ.get("WHISPER_MODEL", "small")
    device = os.environ.get("WHISPER_DEVICE", "cpu")
    compute = os.environ.get("WHISPER_COMPUTE", "int8")
    return WhisperModel(size, device=device, compute_type=compute)


def transcribe_audio(data: bytes, filename: str) -> str:
    suffix = os.path.splitext(filename)[1] or ".m4a"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as f:
        f.write(data)
        f.flush()
        segments, _info = _model().transcribe(f.name, language="zh", beam_size=5)
        return "".join(seg.text for seg in segments).strip()

"""Short spoken lines for lessons (prompts, praise, hints, choice names, greeting).

The voice is a friendly narrator, never the teacher. Sources, best first:
1. the best installed Apple voice (Siri natural / Premium / Enhanced) through a tiny
   AVSpeechSynthesizer helper, at the voice's native rate (48 kHz neural voices);
2. the classic `say` voices.
(The second brain's model gateway has no Gemini TTS model, so it is not a source.)
Every clip is finished the same way: loudness-normalised (-16 LUFS, true peak -2 dB),
30 ms fades, AAC 128k / 44.1 kHz mono, and refused unless its peak is below -1 dBFS.
Finished clips are cached by (text, source, style) so regeneration does not re-render.
When nothing can speak, callers fall back to text-only prompts.
"""
from __future__ import annotations

from functools import lru_cache
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

MAX_SPOKEN_CHARS = 160
MAX_CLIP_SECONDS = 15
PIPELINE = "bubu-tts-2"
LOUDNESS = "I=-16:TP=-2:LRA=11"
MAX_PEAK_DB = -1.0
FADE_SECONDS = 0.03
# Warm, unhurried narrator: a little slower than default (0.5), a touch brighter.
STYLE = {"rate": 0.44, "pitch": 1.05}
# Siri's natural Mandarin voice reads the English words in mixed lines clearly too.
NEURAL_VOICES = ("com.apple.siri.natural.Li-Mu",)
HELPER_SOURCE = Path(__file__).with_name("tts_helper.swift")
# Preference order; only voices the machine actually has are used.
VOICES = {"zh": ("Tingting", "Meijia", "Flo"), "en": ("Samantha", "Karen", "Flo")}
RATES = {"zh": "165", "en": "150"}  # a little slower than default for a toddler
_LINE = re.compile(r"^(.+?)\s+([a-z]{2,3}_[A-Z]{2,3})\s+#")
HAN = re.compile(r"[㐀-鿿]")


def language_of(text: str) -> str:
    return "zh" if HAN.search(text) else "en"


# ---- source 1: best Apple voice through the AVSpeechSynthesizer helper ---------------------

def neural_helper() -> list[str] | None:
    """Command that runs the helper. It runs under Apple's `swift` interpreter on purpose: a self-compiled
    binary is not shown the Siri natural voices, the Apple-signed toolchain is (about 1 s per line)."""
    swift = os.environ.get("LEARNING_TTS_SWIFT") or "/usr/bin/swift"
    if not HELPER_SOURCE.is_file() or not Path(swift).is_file() or not os.access(swift, os.X_OK):
        return None
    return [swift, str(HELPER_SOURCE)]


def neural_source(text: str, language: str, workdir: Path) -> Path | None:
    helper = neural_helper()
    if not helper:
        return None
    script, raw = workdir / "line.txt", workdir / "neural.caf"
    script.write_text(text, encoding="utf-8")
    try:
        result = subprocess.run([*helper, ",".join(NEURAL_VOICES), "zh-CN" if language == "zh" else "en-US",
                                 str(STYLE["rate"]), str(STYLE["pitch"]), str(script), str(raw)],
                                capture_output=True, timeout=120, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return raw if result.returncode == 0 and raw.is_file() and raw.stat().st_size else None


# ---- source 2: classic `say` voices ---------------------------------------------------------

@lru_cache(maxsize=1)
def installed_voices() -> dict[str, str]:
    """Base voice name -> locale from `say -v ?` (e.g. "Tingting (中文（中国大陆）)" -> Tingting)."""
    try:
        result = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        return {}
    voices = {}
    for line in result.stdout.splitlines():
        match = _LINE.match(line)
        if match:
            name = re.sub(r"\s*\(.*\)$", "", match.group(1)).strip()
            voices.setdefault(name, match.group(2))
    return voices


def pick_voice(language: str, voices: dict[str, str] | None = None) -> str | None:
    voices = installed_voices() if voices is None else voices
    prefix = "zh_" if language == "zh" else "en_"
    for name in VOICES[language]:
        if voices.get(name, "").startswith(prefix):
            return name
    return None


def say_source(text: str, language: str, workdir: Path) -> Path | None:
    voice = pick_voice(language)
    if not voice:
        return None
    # The text goes through a file, never the command line, so a leading "-" is not an option.
    script, raw = workdir / "line.txt", workdir / "say.aiff"
    script.write_text(text, encoding="utf-8")
    try:
        spoken = subprocess.run(["say", "-v", voice, "-r", RATES[language], "-o", str(raw), "-f", str(script)],
                                capture_output=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return raw if spoken.returncode == 0 and raw.is_file() and raw.stat().st_size else None


SOURCES = (("apple-best", neural_source), ("say", say_source))


# ---- finishing: one clean, consistent clip whatever the source ------------------------------

def _ffmpeg(ffmpeg: str, args: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run([ffmpeg, "-hide_banner", "-nostats", *args], capture_output=True, text=True, timeout=timeout, check=False)


def volume(path: Path, ffmpeg: str = "ffmpeg") -> tuple[float, float] | None:
    """(max_volume, mean_volume) in dB from ffmpeg volumedetect."""
    result = _ffmpeg(ffmpeg, ["-i", str(path), "-af", "volumedetect", "-f", "null", "-"])
    peak = re.search(r"max_volume:\s*(-?[\d.]+|-inf) dB", result.stderr)
    mean = re.search(r"mean_volume:\s*(-?[\d.]+|-inf) dB", result.stderr)
    if result.returncode or not peak or not mean:
        return None
    return float(peak.group(1)), float(mean.group(1))


def finish(raw: Path, target: Path, *, ffmpeg: str = "ffmpeg") -> bool:
    """Native-rate source -> normalised, faded, AAC 128k 44.1 kHz mono; False if it would clip or is silent."""
    trim = "atrim=0:%d" % MAX_CLIP_SECONDS
    measured = _ffmpeg(ffmpeg, ["-i", str(raw), "-af", "%s,loudnorm=%s:print_format=json" % (trim, LOUDNESS), "-f", "null", "-"])
    match = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", measured.stderr)
    norm = "loudnorm=" + LOUDNESS
    if measured.returncode == 0 and match:
        try:
            m = json.loads(match.group(0))
            values = [float(m[k]) for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")]
            if all(abs(v) < 1000 for v in values):
                norm += (":measured_I=%.2f:measured_TP=%.2f:measured_LRA=%.2f:measured_thresh=%.2f:offset=%.2f:linear=true"
                         % tuple(values))
        except (ValueError, KeyError):
            pass
    fades = "afade=t=in:d={0},areverse,afade=t=in:d={0},areverse".format(FADE_SECONDS)
    for extra in ("", ",volume=-3dB"):
        chain = "%s,%s,aresample=44100,%s%s" % (trim, norm, fades, extra)
        encoded = _ffmpeg(ffmpeg, ["-i", str(raw), "-af", chain, "-ac", "1", "-ar", "44100", "-c:a", "aac", "-b:a", "128k",
                                   "-movflags", "+faststart", "-y", str(target)])
        if encoded.returncode or not target.is_file() or not target.stat().st_size:
            return False
        levels = volume(target, ffmpeg)
        if levels is None:
            return False
        peak, mean = levels
        if mean < -60:
            return False
        if peak < MAX_PEAK_DB:
            return True
    target.unlink(missing_ok=True)
    return False


def cache_key(text: str, source: str) -> str:
    return hashlib.sha256(json.dumps([PIPELINE, source, NEURAL_VOICES, STYLE, LOUDNESS, text],
                                     ensure_ascii=False).encode()).hexdigest()


def synthesize(text: str, target: Path, *, ffmpeg: str = "ffmpeg", cache_dir: Path | None = None, sources=None) -> bool:
    """Write a short mono AAC clip of `text` to `target`; False when no voice/tool is available."""
    text = " ".join(str(text).split())[:MAX_SPOKEN_CHARS]
    if not text:
        return False
    language = language_of(text)
    for name, source in (SOURCES if sources is None else sources):
        cached = Path(cache_dir) / (cache_key(text, name) + ".m4a") if cache_dir else None
        if cached and cached.is_file() and cached.stat().st_size:
            shutil.copyfile(cached, target)
            return True
        with tempfile.TemporaryDirectory(prefix="bubu-tts-") as tmp:
            try:
                raw = source(text, language, Path(tmp))
                if raw is None or not finish(raw, Path(target), ffmpeg=ffmpeg):
                    continue
            except (OSError, subprocess.SubprocessError):
                continue
        if cached:
            try:
                cached.parent.mkdir(parents=True, exist_ok=True)
                temporary = cached.with_suffix(".%d.tmp" % os.getpid())
                shutil.copyfile(target, temporary)
                os.replace(temporary, cached)
            except OSError:
                pass
        return True
    return False

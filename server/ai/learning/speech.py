"""Short spoken prompts for lessons, made on this Mac with the system `say` voices.

The prompt voice does not pretend to be the teacher: it is a friendly narrator.
When `say` or a matching voice is missing, callers fall back to text-only prompts.
"""
from __future__ import annotations

from functools import lru_cache
import re
import subprocess
import tempfile
from pathlib import Path

MAX_SPOKEN_CHARS = 160
MAX_CLIP_SECONDS = 12
# Preference order; only voices the machine actually has are used.
VOICES = {"zh": ("Tingting", "Meijia", "Flo"), "en": ("Samantha", "Karen", "Flo")}
RATES = {"zh": "165", "en": "150"}  # a little slower than default for a toddler
_LINE = re.compile(r"^(.+?)\s+([a-z]{2,3}_[A-Z]{2,3})\s+#")
HAN = re.compile(r"[㐀-鿿]")


def language_of(text: str) -> str:
    return "zh" if HAN.search(text) else "en"


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


def synthesize(text: str, target: Path, *, ffmpeg: str = "ffmpeg") -> bool:
    """Write a short mono AAC clip of `text` to `target`; False when no voice/tool is available."""
    text = " ".join(str(text).split())[:MAX_SPOKEN_CHARS]
    language = language_of(text)
    voice = pick_voice(language)
    if not text or not voice:
        return False
    with tempfile.TemporaryDirectory(prefix="bubu-say-") as tmp:
        raw = Path(tmp) / "speech.aiff"
        try:
            # The text goes through a file, never the command line, so a leading "-" is not an option.
            script = Path(tmp) / "speech.txt"
            script.write_text(text, encoding="utf-8")
            spoken = subprocess.run(["say", "-v", voice, "-r", RATES[language], "-o", str(raw), "-f", str(script)],
                                    capture_output=True, timeout=30, check=False)
            if spoken.returncode or not raw.is_file() or not raw.stat().st_size:
                return False
            converted = subprocess.run([ffmpeg, "-v", "error", "-i", str(raw), "-t", str(MAX_CLIP_SECONDS), "-ac", "1",
                                        "-ar", "44100", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart",
                                        "-y", str(target)], capture_output=True, timeout=60, check=False)
        except (OSError, subprocess.SubprocessError):
            return False
    return converted.returncode == 0 and Path(target).is_file() and Path(target).stat().st_size > 0

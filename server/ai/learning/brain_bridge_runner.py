"""One explicit Gemini request in second-brain's own Python environment.

No daemon, scanning, model fallback, or credentials are exported to Bubu.
"""
import contextlib
import base64
import binascii
import io
import json
from pathlib import Path
import sys


MAX_REQUEST_BYTES = 24 * 1024 * 1024


def validate_request(system, user, schema):
    """Only text and bounded inline media; never fetch client-provided URLs."""
    if not isinstance(system, str) or not isinstance(schema, dict):
        raise ValueError("模型请求格式无效")
    text_bytes = len(system.encode())
    if isinstance(user, str):
        text_bytes += len(user.encode())
    elif isinstance(user, list) and 0 < len(user) <= 24:
        for part in user:
            if not isinstance(part, dict):
                raise ValueError("模型媒体格式无效")
            if part.get("type") == "text" and set(part) == {"type", "text"} and isinstance(part["text"], str):
                text_bytes += len(part["text"].encode())
                continue
            media = part.get("image_url")
            if (part.get("type") != "image_url" or set(part) != {"type", "image_url"}
                    or not isinstance(media, dict) or set(media) - {"url", "detail"}
                    or media.get("detail", "auto") not in {"auto", "low", "high"}):
                raise ValueError("模型媒体格式无效")
            value = media.get("url")
            if not isinstance(value, str) or len(value) > MAX_REQUEST_BYTES:
                raise ValueError("模型媒体过大或格式无效")
            prefix, separator, encoded = value.partition(",")
            if not separator or prefix not in {"data:image/jpeg;base64", "data:image/png;base64",
                                              "data:image/webp;base64", "data:video/mp4;base64"}:
                raise ValueError("只接受本次提交的图片或视频数据")
            try:
                binary = base64.b64decode(encoded, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise ValueError("模型媒体编码无效") from exc
            valid = {
                "data:image/jpeg;base64": binary.startswith(b"\xff\xd8\xff"),
                "data:image/png;base64": binary.startswith(b"\x89PNG\r\n\x1a\n"),
                "data:image/webp;base64": binary.startswith(b"RIFF") and binary[8:12] == b"WEBP",
                "data:video/mp4;base64": binary[4:8] == b"ftyp",
            }[prefix]
            if not valid:
                raise ValueError("模型媒体类型与内容不符")
    else:
        raise ValueError("模型请求格式无效")
    if text_bytes > 1_000_000:
        raise ValueError("模型文本过大")
    request = {"system": system, "user": user, "schema": schema}
    if len(json.dumps(request, ensure_ascii=False, allow_nan=False).encode()) > MAX_REQUEST_BYTES:
        raise ValueError("模型请求过大")
    return request


def main() -> int:
    try:
        root = Path(sys.argv[1]).resolve(strict=True)
        if not (root / "app/brain.py").is_file() or not (root / "data").is_dir():
            raise ValueError()
        raw = sys.stdin.read(MAX_REQUEST_BYTES + 1)
        if len(raw.encode()) > MAX_REQUEST_BYTES:
            raise ValueError()
        request = json.loads(raw)
        effort = request.get("effort", "high")
        if effort not in {"low", "medium", "high"}:
            raise ValueError()
        request = validate_request(request["system"], request["user"], request["schema"])
        sys.path.insert(0, str(root / "app"))
        # Keep any library diagnostics off the JSON channel. Failure responses
        # never include exception text, provider responses or private config.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            import brain
            brain.ANALYSIS_CONTEXT.active = True
            brain.PURPOSE.name = "bubu_learning"
            value = brain.chat(
                [{"role": "system", "content": request["system"]}, {"role": "user", "content": request["user"]}],
                json_mode=True, effort=effort, schema=request["schema"],
            )
            result = json.loads(value)
            if not isinstance(result, dict):
                raise ValueError()
            output = json.dumps({"ok": True, "result": result}, ensure_ascii=False, allow_nan=False)
            if len(output.encode()) > 1_000_000:
                raise ValueError()
        print(output)
        return 0
    except Exception:
        print('{"ok":false,"error":"brain_unavailable"}')
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

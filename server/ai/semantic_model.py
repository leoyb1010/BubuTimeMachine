"""MobileCLIP 懒加载适配器。

主 AI 服务不强制安装 torch/mobileclip；只有显式开启语义搜索并首次请求/worker 建索引时
才加载模型。部署前先运行 scripts/install_semantic_model.sh 下载官方权重。
"""
from __future__ import annotations

import os
import warnings
from pathlib import Path
from threading import Lock
from typing import Sequence


class SemanticModelUnavailable(RuntimeError):
    pass


class MobileCLIPEncoder:
    def __init__(self) -> None:
        self.model_name = os.environ.get("SEMANTIC_MODEL_NAME", "mobileclip_s0")
        self.checkpoint = Path(os.environ.get("SEMANTIC_MODEL_PATH", "")).expanduser()
        self.model_version = os.environ.get(
            "SEMANTIC_MODEL_VERSION", "mobileclip-s0-datacompdr-1b"
        )
        self._lock = Lock()
        self._inference_lock = Lock()
        self._loaded = False
        self._torch = None
        self._model = None
        self._preprocess = None
        self._tokenizer = None
        self._device = "cpu"

    def _load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            if not str(self.checkpoint) or not self.checkpoint.is_file():
                raise SemanticModelUnavailable(
                    "未找到 MobileCLIP 权重，请设置 SEMANTIC_MODEL_PATH"
                )
            try:
                import torch
                # Apple MobileCLIP 当前仍从 timm 的兼容命名空间导入；仅压掉这一条已知
                # 上游 FutureWarning，其他依赖/运行告警继续暴露。
                with warnings.catch_warnings():
                    warnings.filterwarnings(
                        "ignore",
                        message="Importing from timm.models.layers is deprecated.*",
                        category=FutureWarning,
                    )
                    import mobileclip
            except ImportError as exc:
                raise SemanticModelUnavailable(
                    "未安装 MobileCLIP 可选依赖，请运行 install_semantic_model.sh"
                ) from exc

            # 上游 0.1.0 读取内置 JSON 时未用 with 关闭文件；只压掉指向其 configs
            # 目录的 ResourceWarning，模型/权重/推理告警仍照常暴露。
            with warnings.catch_warnings():
                warnings.filterwarnings(
                    "ignore",
                    message="unclosed file .*mobileclip/configs/.*\\.json.*",
                    category=ResourceWarning,
                )
                model, _, preprocess = mobileclip.create_model_and_transforms(
                    self.model_name, pretrained=str(self.checkpoint)
                )
                tokenizer = mobileclip.get_tokenizer(self.model_name)
            device = "mps" if torch.backends.mps.is_available() else "cpu"
            model = model.eval().to(device)
            self._torch = torch
            self._model = model
            self._preprocess = preprocess
            self._tokenizer = tokenizer
            self._device = device
            self._loaded = True

    def encode_text(self, text: str) -> Sequence[float]:
        self._load()
        assert self._torch is not None and self._model is not None
        assert self._tokenizer is not None
        tokens = self._tokenizer([text]).to(self._device)
        with self._inference_lock, self._torch.inference_mode():
            features = self._model.encode_text(tokens)
            features = features / features.norm(dim=-1, keepdim=True)
        return features[0].detach().float().cpu().tolist()

    def encode_image(self, image_path: Path) -> Sequence[float]:
        self._load()
        assert self._torch is not None and self._model is not None
        assert self._preprocess is not None
        try:
            from PIL import Image
        except ImportError as exc:
            raise SemanticModelUnavailable("未安装 Pillow") from exc
        with Image.open(image_path) as image:
            tensor = self._preprocess(image.convert("RGB")).unsqueeze(0).to(self._device)
        with self._inference_lock, self._torch.inference_mode():
            features = self._model.encode_image(tensor)
            features = features / features.norm(dim=-1, keepdim=True)
        return features[0].detach().float().cpu().tolist()

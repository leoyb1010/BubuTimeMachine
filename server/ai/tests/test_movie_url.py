"""movie_render 的 SSRF/LFI URL 白名单回归测试。

覆盖：file:// / 私网 / 云元数据 / 同机其它端口 / 站外 host / ftp·gopher 全拒；
白名单内的 loopback 与公网 https 放行；空白名单 fail-closed；重定向重新校验；
_download 对非法 URL 直接短路不发起网络请求。
全程 monkeypatch getaddrinfo，绝不触真实网络/DNS。
"""
import socket

import pytest

import movie_render as mr


def _fake_getaddrinfo(mapping):
    """构造一个假的 getaddrinfo：按 host 返回预设 IP；未登记的抛 gaierror。"""
    def _inner(host, port, *a, **k):
        if host in mapping:
            return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "",
                     (mapping[host], port or 0))]
        raise socket.gaierror(f"no fake dns for {host}")
    return _inner


@pytest.fixture
def whitelist_pb(monkeypatch):
    """白名单：自托管 loopback PB(127.0.0.1:8090) + 一个公网 host。"""
    monkeypatch.setattr(mr, "_ALLOWED_HOSTS", {"127.0.0.1:8090", "pb.example.com"})
    monkeypatch.setattr(
        mr.socket, "getaddrinfo",
        _fake_getaddrinfo({"127.0.0.1": "127.0.0.1", "pb.example.com": "93.184.216.34",
                           "169.254.169.254": "169.254.169.254", "10.0.0.1": "10.0.0.1"}),
    )


# ---- 应放行 ----

def test_allow_loopback_pb(whitelist_pb):
    assert mr._is_allowed_url("http://127.0.0.1:8090/api/files/x/y/photo.jpg") is True


def test_allow_public_https(whitelist_pb):
    assert mr._is_allowed_url("https://pb.example.com/api/files/x/y/photo.jpg") is True


# ---- 应拒绝 ----

@pytest.mark.parametrize("url", [
    "file:///etc/passwd",                     # LFI：本地文件
    "http://169.254.169.254/latest/meta-data/",  # 云元数据（链路本地）
    "http://10.0.0.1/",                        # 私网横向探测
    "http://127.0.0.1:6379/",                  # 同机其它端口(redis)——端口不在白名单
    "http://evil.com/photo.jpg",               # 站外 host
    "ftp://127.0.0.1:8090/x",                  # 非 http(s) 协议
    "gopher://127.0.0.1:8090/x",
])
def test_reject(url, whitelist_pb):
    assert mr._is_allowed_url(url) is False


def test_reject_metadata_even_if_not_whitelisted_host(whitelist_pb):
    # 169.254.169.254 host 根本不在白名单，第一关就该拒
    assert mr._is_allowed_url("http://169.254.169.254:80/") is False


# ---- 空白名单 = fail-closed ----

def test_empty_whitelist_rejects_everything(monkeypatch):
    monkeypatch.setattr(mr, "_ALLOWED_HOSTS", set())
    # 连合法 loopback 也拒
    assert mr._is_allowed_url("http://127.0.0.1:8090/x") is False
    assert mr._is_allowed_url("https://pb.example.com/x") is False


# ---- _download 对非法 URL 短路，不发起任何网络请求 ----

def test_download_shortcircuits_illegal(monkeypatch, tmp_path):
    monkeypatch.setattr(mr, "_ALLOWED_HOSTS", {"127.0.0.1:8090"})
    called = {"open": False}

    def _boom(*a, **k):
        called["open"] = True
        raise AssertionError("网络请求不应被发起")

    monkeypatch.setattr(mr._opener, "open", _boom)
    dest = tmp_path / "out.jpg"
    assert mr._download("file:///etc/passwd", str(dest)) is False
    assert mr._download("http://169.254.169.254/", str(dest)) is False
    assert called["open"] is False
    assert not dest.exists()


# ---- 重定向必须重新校验（不能只校验首个 URL）----

def test_redirect_to_disallowed_blocked(whitelist_pb):
    from urllib.error import URLError

    handler = mr._ValidatingRedirectHandler()
    # 从白名单内的 URL 302 到 file:// / 元数据，应抛 URLError 而非跟随
    with pytest.raises(URLError):
        handler.redirect_request(None, None, 302, "Found", {},
                                 "http://169.254.169.254/latest/meta-data/")
    with pytest.raises(URLError):
        handler.redirect_request(None, None, 302, "Found", {}, "file:///etc/passwd")


def test_redirect_to_allowed_passes(whitelist_pb):
    # 重定向到白名单内合法 URL 应放行（返回一个 Request，不抛）
    req = handler_req = mr._ValidatingRedirectHandler().redirect_request(
        _DummyReq(), None, 302, "Found", {}, "http://127.0.0.1:8090/api/files/a/b/c.jpg")
    assert handler_req is not None


class _DummyReq:
    """HTTPRedirectHandler.redirect_request 内部会读 req 的若干属性；给足最小桩。"""
    full_url = "http://127.0.0.1:8090/orig"
    def get_full_url(self):
        return self.full_url
    def has_header(self, name):
        return False
    @property
    def headers(self):
        return {}
    unredirected_hdrs = {}
    def get_method(self):
        return "GET"
    data = None
    origin_req_host = "127.0.0.1"
    unverifiable = True
    timeout = None

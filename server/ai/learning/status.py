"""Home-server health for the settings page and /health/deep; never hangs on the external disk.

Readability of the learning store and the library is probed in a short-lived
subprocess with a hard deadline: a process stuck on a stalled disk is killed and
abandoned instead of holding a request thread. Nothing here exposes paths or hosts.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from .online_timeline import LOCAL

WORKER_STALE = 900  # one loop can include several slow model calls
PROBE = r'''
import json, sqlite3, sys
from pathlib import Path
out = {"learning_store": False, "brain_library": False, "heartbeat": None, "backup": None, "backup_marker": None}
def open_ro(path):
    return sqlite3.connect(Path(path).as_uri() + "?mode=ro", uri=True, timeout=2)
if sys.argv[1]:
    try:
        with open_ro(sys.argv[1]) as c:
            for key, name in (("worker-heartbeat", "heartbeat"), ("learning-backup", "backup")):
                row = c.execute("SELECT value FROM cursors WHERE key=?", (key,)).fetchone()
                out[name] = json.loads(row[0]) if row else None
        out["learning_store"] = True
    except Exception:
        pass
if sys.argv[2]:
    try:
        with open_ro(sys.argv[2]) as c:
            c.execute("SELECT count(*) FROM sqlite_master").fetchone()
        out["brain_library"] = True
    except Exception:
        pass
if len(sys.argv) > 3 and sys.argv[3]:
    try:
        marker = Path(sys.argv[3])
        # The nightly mirror's learning folder (or one file in it): the newest of its snapshot files.
        files = [marker / n for n in ("manifest.json", "learning.sqlite", ".bubu-learning-backup")] if marker.is_dir() else [marker]
        times = [f.stat().st_mtime for f in files if f.is_file()]
        out["backup_marker"] = {"at": max(times)} if times else None
    except Exception:
        pass
print(json.dumps(out))
'''


def probe(state_dir=None, brain_root=None, timeout=5.0, marker=None) -> dict:
    """`marker`: the nightly restic mirror's learning backup (LEARNING_BACKUP_MARKER), a folder or a file;
    it lives on the external disk, so it is read in the same killable subprocess."""
    marker = marker if marker is not None else os.environ.get("LEARNING_BACKUP_MARKER", "").strip()
    state_dir = state_dir if state_dir is not None else os.environ.get("LEARNING_STATE_DIR", "").strip()
    brain_root = brain_root if brain_root is not None else os.environ.get("LEARNING_BRAIN_ROOT", "").strip()
    database = str(Path(state_dir).expanduser() / "learning.sqlite") if state_dir else ""
    library = str(Path(brain_root).expanduser() / "data/library.sqlite") if brain_root else ""
    failed = {"learning_store": False, "brain_library": False, "heartbeat": None, "backup": None}
    try:
        process = subprocess.Popen([sys.executable, "-I", "-B", "-c", PROBE, database, library,
                                    str(Path(marker).expanduser()) if marker else ""],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except OSError:
        return failed
    try:
        output, _ = process.communicate(timeout=timeout)
        value = json.loads(output)
        return value if isinstance(value, dict) else failed
    except subprocess.TimeoutExpired:
        process.kill()
        try:
            process.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            pass  # stuck in the kernel on the disk; abandon it rather than wait
        return failed
    except ValueError:
        return failed


def _at(value):
    stamp = value.get("at") if isinstance(value, dict) else None
    return stamp if isinstance(stamp, (int, float)) else None


def _local(stamp):
    return None if stamp is None else datetime.fromtimestamp(stamp, LOCAL).isoformat(timespec="seconds")


def deep_health(snapshot_age=None) -> dict:
    result = probe()
    beat = _at(result.get("heartbeat"))
    return {"ok": bool(result["learning_store"] and result["brain_library"]), "learning_store": result["learning_store"],
            "brain_library": result["brain_library"],
            "worker_heartbeat_age_s": None if beat is None else max(0, int(time.time() - beat)),
            "snapshot_age_s": snapshot_age}


class Status:
    def __init__(self, timeline, probe_fn=probe):
        self.timeline, self.probe = timeline, probe_fn
        self.store, self.family = timeline.store, timeline.family

    def status(self, scope):
        self.timeline.authorize(scope)
        root = getattr(self.timeline.bridge, "root", None)
        result = self.probe(str(self.store.root), str(root) if root else "", 4.0)
        beat = _at(result.get("heartbeat"))
        # The worker's own daily copy or the nightly restic mirror, whichever is newer.
        backups = [b for b in (_at(result.get("backup")), _at(result.get("backup_marker"))) if b is not None]
        backup = max(backups) if backups else None
        snapshot = self.timeline.peek(wait=2.0)
        captions = voices = None
        if result["learning_store"]:
            try:
                if snapshot is not None:
                    captions = len(self.timeline.captions.pending(self.family, [r["item"] for r in snapshot["rows"]]))
                with self.store.db() as db:
                    if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='voices'").fetchone():
                        voices = db.execute("SELECT count(*) FROM voices WHERE family_id=? AND state='pending'",
                                            (self.family,)).fetchone()[0]
            except Exception:
                pass
        brain = result["brain_library"]
        return {"ok": bool(result["learning_store"] and brain), "learning_store": result["learning_store"],
                "brain_library": brain, "worker_alive": None if beat is None else time.time() - beat < WORKER_STALE,
                "worker_heartbeat_at": _local(beat), "snapshot_at": _local(self.timeline.built_at),
                "captions_pending": captions, "voices_pending": voices, "backup_at": _local(backup),
                "items": None if snapshot is None else len(snapshot["rows"]),
                "preparing": snapshot is None and bool(brain),
                "checked_at": datetime.now(timezone.utc).astimezone(LOCAL).isoformat(timespec="seconds")}

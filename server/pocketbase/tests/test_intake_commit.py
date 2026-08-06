"""Isolated PocketBase integration test for the reliable intake commit hook.

Requires POCKETBASE_BIN. It creates a brand-new temporary pb_data directory and
never opens the production database.
"""
from __future__ import annotations

import hashlib
import json
import os
import socket
import sqlite3
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class IntakeCommitIntegrationTests(unittest.TestCase):
    def test_atomic_commit_and_idempotent_replay(self) -> None:
        binary_value = os.environ.get("POCKETBASE_BIN", "").strip()
        if not binary_value:
            self.skipTest("POCKETBASE_BIN is not configured")
        binary = Path(binary_value).expanduser().resolve()
        self.assertTrue(binary.is_file(), "PocketBase binary does not exist")

        with tempfile.TemporaryDirectory(prefix="bubu-pb-intake-") as raw:
            sandbox = Path(raw)
            data_dir = sandbox / "pb_data"
            staging = sandbox / "intake-staging"
            staged_dir = staging / "files" / "batch-test-0001"
            staged_dir.mkdir(parents=True)
            content = b"isolated-bubu-photo-test"
            digest = hashlib.sha256(content).hexdigest()
            media_path = staged_dir / f"{digest}.jpg"
            media_path.write_bytes(content)
            key = "integration-test-intake-key-0000000000000001"
            env = os.environ.copy()
            env.update({
                "INTAKE_COMMIT_KEY": key,
                "INTAKE_STAGING_ROOT": str(staging),
            })

            subprocess.run(
                [
                    str(binary), "migrate", "up", "--dir", str(data_dir),
                    "--migrationsDir", str(ROOT / "server/pocketbase/migrations"),
                    "--hooksDir", str(ROOT / "server/pocketbase/pb_hooks"),
                ],
                check=True,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )

            port = self._free_port()
            process = subprocess.Popen(
                [
                    str(binary), "serve", f"--http=127.0.0.1:{port}",
                    "--dir", str(data_dir),
                    "--migrationsDir", str(ROOT / "server/pocketbase/migrations"),
                    "--hooksDir", str(ROOT / "server/pocketbase/pb_hooks"),
                    "--hooksWatch=false",
                ],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                self._wait_until_ready(port, process)
                manifest = {
                    "id": "batch-test-0001",
                    "owner": "pb:test-user-0001",
                    "family_id": "family-test-0001",
                    "state": "committing",
                    "entry": {
                        "local_id": "entry-test-0001",
                        "happened_at": "2026-08-06T08:00:00Z",
                        "author_role": "爸爸",
                        "note": "isolated integration test",
                        "source": "integration-test",
                    },
                    "items": [{
                        "asset_key": "asset-test-0001",
                        "file_name": "test.jpg",
                        "media_type": "photo",
                        "captured_at": "2026-08-06T08:00:00Z",
                        "resource_role": "display",
                        "asset_group_id": "group-test-0001",
                        "content_hash": digest,
                        "actual_size": len(content),
                        "stored_path": str(media_path),
                    }],
                }
                first = self._post(port, key, manifest)
                self.assertEqual(first[0], 201)
                self.assertFalse(first[1]["idempotent"])
                replay = self._post(port, key, manifest)
                self.assertEqual(replay[0], 200)
                self.assertTrue(replay[1]["idempotent"])
                self.assertEqual(first[1]["entry_id"], replay[1]["entry_id"])

                # 同一原片来自另一批/另一入口时绑定已有事实，不制造第二个 Entry/Media。
                duplicate_dir = staging / "files" / "batch-test-0002"
                duplicate_dir.mkdir(parents=True)
                duplicate_path = duplicate_dir / f"{digest}.jpg"
                duplicate_path.write_bytes(content)
                duplicate = json.loads(json.dumps(manifest))
                duplicate["id"] = "batch-test-0002"
                duplicate["entry"]["local_id"] = "entry-test-0002"
                duplicate["items"][0]["asset_key"] = "asset-test-0002"
                duplicate["items"][0]["stored_path"] = str(duplicate_path)
                deduped = self._post(port, key, duplicate)
                self.assertEqual(deduped[1]["entry_id"], first[1]["entry_id"])

                # 多媒体中第二个文件无效时，前面的 Entry/Media 也必须整体回滚。
                rollback_dir = staging / "files" / "batch-test-0003"
                rollback_dir.mkdir(parents=True)
                fresh_content = b"fresh-valid-file"
                fresh_digest = hashlib.sha256(fresh_content).hexdigest()
                fresh_path = rollback_dir / f"{fresh_digest}.jpg"
                fresh_path.write_bytes(fresh_content)
                bad = json.loads(json.dumps(manifest))
                bad["id"] = "batch-test-0003"
                bad["entry"]["local_id"] = "entry-test-0003"
                bad["items"] = [
                    {
                        **bad["items"][0], "asset_key": "asset-test-0003",
                        "content_hash": fresh_digest, "actual_size": len(fresh_content),
                        "stored_path": str(fresh_path),
                    },
                    {
                        **bad["items"][0], "asset_key": "asset-test-0004",
                        "content_hash": "f" * 64, "actual_size": 1,
                        "stored_path": str(rollback_dir / "missing.jpg"),
                    },
                ]
                self.assertGreaterEqual(self._post_error(port, key, bad), 400)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                if process.stdout:
                    process.stdout.close()

            database = data_dir / "data.db"
            with sqlite3.connect(database) as db:
                entries = db.execute(
                    "SELECT count(*) FROM entries WHERE intakeBatchId=?",
                    ("batch-test-0001",),
                ).fetchone()[0]
                media = db.execute(
                    "SELECT count(*) FROM media WHERE intakeBatchId=? AND contentHash=?",
                    ("batch-test-0001", digest),
                ).fetchone()[0]
                rolled_back_entries = db.execute(
                    "SELECT count(*) FROM entries WHERE intakeBatchId=?",
                    ("batch-test-0003",),
                ).fetchone()[0]
                rolled_back_media = db.execute(
                    "SELECT count(*) FROM media WHERE intakeBatchId=?",
                    ("batch-test-0003",),
                ).fetchone()[0]
            self.assertEqual(entries, 1)
            self.assertEqual(media, 1)
            self.assertEqual(rolled_back_entries, 0)
            self.assertEqual(rolled_back_media, 0)
            stored = list((data_dir / "storage").rglob("*.jpg"))
            self.assertEqual(len(stored), 1)
            self.assertEqual(stored[0].read_bytes(), content)

    @staticmethod
    def _free_port() -> int:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])

    @staticmethod
    def _wait_until_ready(port: int, process: subprocess.Popen[str]) -> None:
        deadline = time.time() + 15
        while time.time() < deadline:
            if process.poll() is not None:
                output = process.stdout.read() if process.stdout else ""
                raise AssertionError(f"PocketBase stopped during startup: {output}")
            try:
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/api/health", timeout=0.5
                ) as response:
                    if response.status == 200:
                        return
            except (OSError, urllib.error.URLError):
                time.sleep(0.1)
        raise AssertionError("PocketBase did not become ready")

    @staticmethod
    def _post(port: int, key: str, manifest: dict) -> tuple[int, dict]:
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/bubu/intake/commit",
            data=json.dumps(manifest).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "X-Bubu-Intake-Key": key,
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise AssertionError(f"commit hook returned {error.code}: {detail}") from error

    @staticmethod
    def _post_error(port: int, key: str, manifest: dict) -> int:
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/bubu/intake/commit",
            data=json.dumps(manifest).encode("utf-8"),
            headers={"Content-Type": "application/json", "X-Bubu-Intake-Key": key},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status
        except urllib.error.HTTPError as error:
            error.read()
            return error.code


if __name__ == "__main__":
    unittest.main()

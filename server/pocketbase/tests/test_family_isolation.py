"""Exercise actual PocketBase rules in a fresh disposable database, without family data."""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from server.pocketbase.tests import test_intake_commit as intake_helpers

ROOT = intake_helpers.ROOT


class FamilyIsolationIntegrationTests(unittest.TestCase):
    def setUp(self):
        binary = os.environ.get("POCKETBASE_BIN", "")
        if not binary:
            self.skipTest("POCKETBASE_BIN is not configured")
        self.sandbox = tempfile.TemporaryDirectory(prefix="bubu-pb-family-")
        self.addCleanup(self.sandbox.cleanup)
        data = Path(self.sandbox.name) / "pb_data"
        args = ["--dir", str(data), "--migrationsDir", str(ROOT / "server/pocketbase/migrations"),
                "--hooksDir", str(ROOT / "server/pocketbase/pb_hooks")]
        subprocess.run([binary, "migrate", "up", *args], check=True, capture_output=True)
        subprocess.run([binary, "superuser", "upsert", "audit@example.invalid",
                        "isolated-audit-password-123", *args], check=True, capture_output=True)
        port = intake_helpers.IntakeCommitIntegrationTests._free_port()
        self.base = f"http://127.0.0.1:{port}"
        self.process = subprocess.Popen([binary, "serve", f"--http=127.0.0.1:{port}",
                                         "--hooksWatch=false", *args],
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(self.stop)
        intake_helpers.IntakeCommitIntegrationTests._wait_until_ready(port, self.process)
        self.admin = self.call("POST", "/api/collections/_superusers/auth-with-password",
                               {"identity": "audit@example.invalid", "password": "isolated-audit-password-123"})[1]["token"]
        self.family_a = self.create("families", {"name": "Audit A"})["id"]
        self.family_b = self.create("families", {"name": "Audit B"})["id"]
        self.user_a, self.token_a = self.user("a", self.family_a)
        _, self.token_b = self.user("b", self.family_b)
        _, self.token_unassigned = self.user("unassigned", "")
        self.entry_a = self.create("entries", self.entry("a", self.family_a))
        self.entry_b = self.create("entries", self.entry("b", self.family_b))

    def stop(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self.process.stdout.close()

    def call(self, method, path, body=None, token=None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(self.base + path, method=method, headers=headers,
                                         data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def create(self, collection, body):
        status, result = self.call("POST", f"/api/collections/{collection}/records", body, self.admin)
        self.assertLess(status, 300, result)
        return result

    def user(self, name, family):
        email = f"{name}@example.invalid"
        record = self.create("users", {"email": email, "password": "test-password-123",
                                       "passwordConfirm": "test-password-123", "familyId": family})
        status, auth = self.call("POST", "/api/collections/users/auth-with-password",
                                 {"identity": email, "password": "test-password-123"})
        self.assertEqual(status, 200)
        return record, auth["token"]

    @staticmethod
    def entry(local_id, family):
        return {"localId": local_id, "familyId": family, "happenedAt": "2026-09-08 00:00:00.000Z",
                "authorRole": "audit", "note": "synthetic"}

    def test_fresh_install_denies_unassigned_and_other_family(self):
        for token, ids in [(self.token_a, [self.entry_a["id"]]), (self.token_b, [self.entry_b["id"]]),
                           (self.token_unassigned, [])]:
            status, listing = self.call("GET", "/api/collections/entries/records", token=token)
            self.assertEqual(status, 200)
            self.assertEqual([row["id"] for row in listing["items"]], ids)
        status, _ = self.call("GET", "/api/collections/entries/records/" + self.entry_b["id"], token=self.token_a)
        self.assertEqual(status, 404)
        status, listing = self.call("GET", "/api/collections/families/records", token=self.token_unassigned)
        self.assertEqual(status, 200)
        self.assertEqual(listing["items"], [])

    def test_business_record_cannot_be_transferred_to_another_family(self):
        path = "/api/collections/entries/records/" + self.entry_a["id"]
        status, _ = self.call("PATCH", path, {"familyId": self.family_b}, self.token_a)
        self.assertGreaterEqual(status, 400)
        status, row = self.call("PATCH", path, {"note": "edited", "familyId": self.family_a}, self.token_a)
        self.assertEqual(status, 200)
        self.assertEqual(row["familyId"], self.family_a)
        status, _ = self.call("PATCH", path, {"isDeleted": True}, self.token_a)
        self.assertEqual(status, 200)

    def test_user_cannot_change_membership_or_create_cross_family(self):
        status, _ = self.call("PATCH", "/api/collections/users/records/" + self.user_a["id"],
                              {"familyId": ""}, self.token_a)
        self.assertGreaterEqual(status, 400)
        for token, family in [(self.token_a, self.family_b), (self.token_unassigned, "")]:
            status, _ = self.call("POST", "/api/collections/entries/records", self.entry("blocked", family), token)
            self.assertGreaterEqual(status, 400)

    def test_capsule_crypto_version_cannot_be_downgraded(self):
        capsule = self.create("timecapsules", {"localId": "capsule-a", "familyId": self.family_a,
                                               "title": "synthetic", "fromRole": "audit",
                                               "unlockAt": "2040-01-01 00:00:00.000Z", "cryptoVersion": 3})
        path = "/api/collections/timecapsules/records/" + capsule["id"]
        status, _ = self.call("PATCH", path, {"cryptoVersion": 2}, self.token_a)
        self.assertGreaterEqual(status, 400)
        status, row = self.call("PATCH", path, {"title": "updated"}, self.token_a)
        self.assertEqual(status, 200)
        self.assertEqual(row["cryptoVersion"], 3)

    # ---------- 2026-09-12 第一轮加固回归 ----------

    def multipart(self, path, fields, file_field, file_name, content, token):
        boundary = "----bubu-audit-boundary"
        body = b""
        for key, value in fields.items():
            body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n").encode()
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{file_name}\"\r\n"
                 f"Content-Type: image/jpeg\r\n\r\n").encode() + content + b"\r\n"
        body += f"--{boundary}--\r\n".encode()
        request = urllib.request.Request(self.base + path, method="POST", data=body, headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}", "Authorization": "Bearer " + token})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def jobs_for(self, media_id):
        query = urllib.parse.quote(f"sourceRecordId='{media_id}'")
        status, listing = self.call("GET", f"/api/collections/automation_jobs/records?filter={query}&perPage=50",
                                    token=self.admin)
        self.assertEqual(status, 200)
        return listing["items"]

    def test_tombstone_cannot_be_revived_and_author_is_immutable(self):
        path = "/api/collections/entries/records/" + self.entry_a["id"]
        status, row = self.call("PATCH", path, {"note": "still alive", "isDeleted": False}, self.token_a)
        self.assertEqual(status, 200, "对活记录重发 isDeleted=false 必须仍然允许（客户端 DTO 会带该字段）")
        status, row = self.call("PATCH", path, {"authorUserId": self.user_a["id"]}, self.token_a)
        self.assertEqual(status, 200, "历史空作者允许补齐")
        status, _ = self.call("PATCH", path, {"authorUserId": "someone-else"}, self.token_a)
        self.assertGreaterEqual(status, 400, "作者归属不可改写")
        status, _ = self.call("PATCH", path, {"isDeleted": True}, self.token_a)
        self.assertEqual(status, 200)
        status, _ = self.call("PATCH", path, {"isDeleted": False}, self.token_a)
        self.assertGreaterEqual(status, 400, "墓碑不能被翻活")
        status, _ = self.call("PATCH", path, {"note": "edit on tombstone"}, self.token_a)
        self.assertEqual(status, 200, "墓碑上的普通字段更新仍允许（保持 isDeleted=true）")

    def test_user_cannot_change_own_role(self):
        path = "/api/collections/users/records/" + self.user_a["id"]
        status, _ = self.call("PATCH", path, {"role": "admin"}, self.token_a)
        self.assertGreaterEqual(status, 400)
        status, _ = self.call("PATCH", path, {"name": "renamed"}, self.token_a)
        self.assertEqual(status, 200)

    def test_hardened_settings_are_applied_by_migration(self):
        status, settings = self.call("GET", "/api/settings", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(settings["trustedProxy"]["headers"], ["CF-Connecting-IP"])
        self.assertTrue(settings["rateLimits"]["enabled"])
        labels = {rule["label"] for rule in settings["rateLimits"]["rules"]}
        self.assertIn("*:auth", labels)
        self.assertNotIn("/api/", labels, "不能对同步/文件读取设总量限制")

    def test_semantic_queue_enqueues_once_per_content_change(self):
        media = self.create("media", {"localId": "m-1", "familyId": self.family_a, "entryLocalId": "a",
                                      "mediaType": "photo"})
        self.assertEqual(len(self.jobs_for(media["id"])), 1)
        for patch in ({"width": 100}, {"height": 200}, {"clientUpdatedAt": "2026-09-12 00:00:00.000Z"}):
            status, _ = self.call("PATCH", "/api/collections/media/records/" + media["id"], patch, self.admin)
            self.assertEqual(status, 200)
        self.assertEqual(len(self.jobs_for(media["id"])), 1, "无关字段更新不得重复入队")
        status, _ = self.call("PATCH", "/api/collections/media/records/" + media["id"], {"isDeleted": True}, self.admin)
        self.assertEqual(status, 200)
        jobs = self.jobs_for(media["id"])
        self.assertEqual(sorted(job["kind"] for job in jobs), ["semantic_media_delete", "semantic_media_upsert"])

    def test_gc_purges_files_but_keeps_tombstone_row(self):
        status, media = self.multipart("/api/collections/media/records",
                                       {"localId": "m-gc", "familyId": self.family_a, "entryLocalId": "a",
                                        "mediaType": "photo"}, "file", "photo.jpg", b"\xff\xd8bytes", self.admin)
        self.assertEqual(status, 200, media)
        self.assertTrue(media["file"])
        status, _ = self.call("PATCH", "/api/collections/media/records/" + media["id"], {"isDeleted": True}, self.admin)
        self.assertEqual(status, 200)
        status, _ = self.call("POST", "/api/bubu/ops/tombstone-gc", {"retentionDays": 0}, self.token_a)
        self.assertEqual(status, 403, "GC 演练入口仅 superuser")
        status, summary = self.call("POST", "/api/bubu/ops/tombstone-gc", {"retentionDays": 0}, self.admin)
        self.assertEqual(status, 200, summary)
        self.assertEqual(summary["errors"], [])
        self.assertEqual(summary["purged"], 1)
        status, row = self.call("GET", "/api/collections/media/records/" + media["id"], token=self.admin)
        self.assertEqual(status, 200, "墓碑行必须保留，否则离线设备会把已删照片复活")
        self.assertTrue(row["isDeleted"])
        self.assertEqual(row["file"], "")
        status, again = self.call("POST", "/api/bubu/ops/tombstone-gc", {"retentionDays": 0}, self.admin)
        self.assertEqual(again["purged"], 0, "已清理的墓碑不重复处理")
        status, _ = self.call("POST", "/api/collections/media/records",
                              {"localId": "m-gc", "familyId": self.family_a, "entryLocalId": "a",
                               "mediaType": "photo"}, self.token_a)
        self.assertGreaterEqual(status, 400, "同 localId 不能再次创建（墓碑仍在，唯一索引拦截）")


class LegacyFamilyMigrationTests(unittest.TestCase):
    def test_ambiguous_legacy_data_blocks_until_ownership_is_explicit(self):
        binary = os.environ.get("POCKETBASE_BIN", "")
        if not binary:
            self.skipTest("POCKETBASE_BIN is not configured")
        for family_count in (0, 2):
            with self.subTest(families=family_count), tempfile.TemporaryDirectory(prefix="bubu-pb-legacy-") as raw:
                sandbox = Path(raw)
                migrations = sandbox / "migrations"
                migrations.mkdir()
                source = ROOT / "server/pocketbase/migrations"
                for path in source.glob("*.js"):
                    if not path.name.startswith("1700000019_"):
                        shutil.copy2(path, migrations / path.name)
                data = sandbox / "data"
                args = [binary, "migrate", "up", "--dir", str(data), "--migrationsDir", str(migrations)]
                subprocess.run(args, check=True, capture_output=True)
                with sqlite3.connect(data / "data.db") as db:
                    db.execute("INSERT INTO entries (id,localId,happenedAt,authorRole,familyId) VALUES (?,?,?,?,?)",
                               ("auditentry00001", "legacy", "2026-09-08 00:00:00.000Z", "audit", ""))
                    for n in range(family_count):
                        db.execute("INSERT INTO families (id,name) VALUES (?,?)", (f"auditfamily000{n}", "audit"))
                path = source / "1700000019_enforce_family_boundaries.js"
                shutil.copy2(path, migrations / path.name)
                blocked = subprocess.run(args, capture_output=True, text=True)
                # PocketBase 0.39.2 的 migrate CLI 即使报错也可能 exit 0；以错误输出
                # 和迁移表/原记录的回读共同验证回滚，不能只相信进程退出码。
                self.assertIn("历史记录尚未分配家庭", blocked.stdout + blocked.stderr)
                with sqlite3.connect(data / "data.db") as db:
                    self.assertEqual(db.execute("SELECT familyId FROM entries").fetchone()[0], "")
                    self.assertEqual(db.execute("SELECT count(*) FROM _migrations WHERE file=?", (path.name,)).fetchone()[0], 0)
                    if family_count == 0:
                        # 明确只有一个家庭后允许对该家庭回填历史资料。
                        db.execute("INSERT INTO families (id,name) VALUES ('auditfamily0000','audit')")
                    else:
                        # 多家庭时必须先由维护者逐条确认归属，迁移不猜测。
                        db.execute("UPDATE entries SET familyId='auditfamily0000'")
                subprocess.run(args, check=True, capture_output=True)
                with sqlite3.connect(data / "data.db") as db:
                    self.assertEqual(db.execute("SELECT familyId FROM entries").fetchone()[0], "auditfamily0000")
                    self.assertEqual(db.execute("SELECT count(*) FROM _migrations WHERE file=?", (path.name,)).fetchone()[0], 1)
                    rule = db.execute("SELECT listRule FROM _collections WHERE name='entries'").fetchone()[0]
                    self.assertNotIn('familyId = ""', rule)


if __name__ == "__main__":
    unittest.main()

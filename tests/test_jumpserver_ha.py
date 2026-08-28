#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest


loader = importlib.machinery.SourceFileLoader(
    "shadow_ha_packages", "bin/shadow-ha-packages")
spec = importlib.util.spec_from_loader(loader.name, loader)
PACKAGES = importlib.util.module_from_spec(spec)
loader.exec_module(PACKAGES)


class PackagePlanTests(unittest.TestCase):
    def test_plan_classifies_without_requesting_changes(self):
        plan = PACKAGES.build_plan(
            {"alpha": "1", "beta": "2"},
            {"alpha": "0", "gamma": "3"})
        self.assertEqual(plan["missing"], ["beta"])
        self.assertEqual(plan["different_versions"], [
            {"package": "alpha", "active": "1", "standby": "0"}])
        self.assertEqual(plan["extra"], ["gamma"])
        rendered = PACKAGES.render(plan)
        self.assertIn("MISSING beta", rendered)
        self.assertIn("VERSION alpha active=1 standby=0", rendered)

    def test_manifest_rejects_malformed_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "packages.tsv")
            path.write_text("invalid\n", encoding="utf-8")
            with self.assertRaises(PACKAGES.PackageError):
                PACKAGES.read_manifest(str(path))

    def test_manifest_rejects_option_like_package_name(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "packages.tsv")
            path.write_text("--install-suggests\t1\n", encoding="utf-8")
            with self.assertRaises(PACKAGES.PackageError):
                PACKAGES.read_manifest(str(path))


class InstallerTests(unittest.TestCase):
    def staged_install(self, role, *extra):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        command = ["bash", "install.sh", "--role", role, "--vip", "192.0.2.100",
                   "--non-interactive", "--destdir", temporary.name]
        if role == "standby":
            command.extend(["--active-address", "192.0.2.10"])
        command.extend(extra)
        subprocess.run(command, check=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, universal_newlines=True)
        return pathlib.Path(temporary.name)

    def test_active_staged_install_contains_exporter_and_role(self):
        root = self.staged_install("active")
        self.assertTrue((root / "usr/local/libexec/shadow-ha/export").is_file())
        role = (root / "etc/jumpserver-ha/role.conf").read_text(encoding="utf-8")
        self.assertIn("JUMPSERVER_HA_ROLE=active", role)

    def test_standby_staged_install_contains_split_units_and_no_enable(self):
        root = self.staged_install("standby")
        self.assertTrue((root / "etc/systemd/system/shadow-ha-sync.service").is_file())
        self.assertTrue((root / "etc/systemd/system/shadow-ha-apply.path").is_file())
        service = (root / "etc/systemd/system/shadow-ha-sync.service").read_text(
            encoding="utf-8")
        self.assertIn("User=shadow-ha", service)

    def test_runtime_key_directory_is_private_and_writable_by_sync_user(self):
        installer = pathlib.Path("install.sh").read_text(encoding="utf-8")
        self.assertIn(
            "install -d -o shadow-ha -g shadow-ha -m 0700 /etc/jumpserver-ha/keys",
            installer)

    def test_active_exporter_home_is_normalized_for_authorized_keys(self):
        installer = pathlib.Path("install.sh").read_text(encoding="utf-8")
        self.assertIn(
            "usermod --home /var/lib/shadow-export --shell /bin/sh shadow-export",
            installer)
        self.assertIn(
            "/var/lib/shadow-export/.ssh/authorized_keys", installer)

    def test_export_staging_does_not_depend_on_small_tmpfs(self):
        exporter = pathlib.Path("bin/shadow-ha-export").read_text(encoding="utf-8")
        installer = pathlib.Path("install.sh").read_text(encoding="utf-8")
        self.assertIn(
            "SHADOW_HA_EXPORT_STATE_DIR:-/var/lib/shadow-ha-export-state", exporter)
        self.assertNotIn("mktemp -d /tmp/shadow-ha-export", exporter)
        self.assertIn(
            "install -d -o root -g root -m 0700 /var/lib/shadow-ha-export-state",
            installer)

    def test_full_clone_policy_is_explicit_and_persisted(self):
        root = self.staged_install("standby", "--full-clone")
        role = (root / "etc/jumpserver-ha/role.conf").read_text(encoding="utf-8")
        self.assertIn("JUMPSERVER_HA_FULL_CLONE=true", role)
        self.assertIn("JUMPSERVER_HA_SYNC_SECRETS=true", role)
        self.assertEqual((root / "etc/jumpserver-ha/role.conf").stat().st_mode & 0o777,
                         0o644)

    def test_updater_reinstalls_the_configured_role(self):
        updater = pathlib.Path("bin/jumpserver-ha-update").read_text(encoding="utf-8")
        self.assertIn('--role "$JUMPSERVER_HA_ROLE"', updater)
        self.assertNotIn("--role standby --active-address", updater)

    def test_installer_rejects_root_sync_path(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([
                "bash", "install.sh", "--role", "active", "--vip", "192.0.2.100",
                "--sync-path", "/", "--non-interactive", "--destdir", directory],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unsafe sync path", result.stderr)


class ExportContractTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("rsync"), "rsync is an installer prerequisite")
    def test_export_contains_metadata_and_only_approved_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            config = root / "config"
            config.mkdir()
            approved = root / "approved"
            approved.mkdir()
            (approved / "state.txt").write_text("safe\n", encoding="utf-8")
            (approved / ".config/gr").mkdir(parents=True)
            (approved / ".config/gr/credentials").write_text(
                "must-not-export\n", encoding="utf-8")
            (config / "role.conf").write_text(
                "JUMPSERVER_HA_ROLE=active\nJUMPSERVER_HA_FULL_CLONE=false\n",
                encoding="utf-8")
            (config / "sync-paths").write_text(str(approved) + "\n", encoding="utf-8")
            (config / "sync-users").write_text("", encoding="utf-8")
            archive = root / "export.tar.gz"
            environment = dict(
                os.environ,
                SHADOW_HA_CONFIG_DIR=str(config),
                SHADOW_HA_EXPORT_STATE_DIR=str(root / "export-state"))
            with archive.open("wb") as output:
                result = subprocess.run(["bash", "bin/shadow-ha-export"], env=environment,
                                        stdout=output, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            with tarfile.open(str(archive), "r:gz") as exported:
                names = exported.getnames()
                self.assertIn("metadata/users.tsv", names)
                self.assertIn("metadata/shadow", names)
                self.assertIn("metadata/packages.tsv", names)
                expected = "rootfs" + str(approved).replace("\\", "/") + "/state.txt"
                self.assertIn(expected.lstrip("/"), names)
                self.assertFalse(any(name.endswith("/.config/gr/credentials")
                                     for name in names))
                shadow = exported.extractfile("metadata/shadow").read()
                self.assertEqual(shadow, b"")


class StaticContractTests(unittest.TestCase):
    def test_linux_entrypoints_use_lf_line_endings(self):
        paths = [pathlib.Path("install.sh")]
        paths.extend(path for path in pathlib.Path("bin").iterdir() if path.is_file())
        for path in paths:
            with self.subTest(path=str(path)):
                self.assertNotIn(b"\r\n", path.read_bytes())

    def test_motd_mentions_users_homes_and_package_proposal(self):
        motd = pathlib.Path("templates/motd-standby").read_text(encoding="utf-8")
        self.assertIn("users, home directories", motd)
        self.assertIn("shadow-ha-packages plan", motd)
        self.assertIn("Full-clone mode", motd)

    def test_full_clone_archive_contract_protects_local_authentication(self):
        exporter = pathlib.Path("bin/shadow-ha-export").read_text(encoding="utf-8")
        apply = pathlib.Path("bin/shadow-ha-apply").read_text(encoding="utf-8")
        sync = pathlib.Path("bin/shadow-ha-sync").read_text(encoding="utf-8")
        self.assertIn("format=shadow-ha-v3", exporter)
        self.assertIn('chmod 0600 "$stage/metadata/shadow"', exporter)
        self.assertIn("full_clone", exporter)
        self.assertIn("metadata/shadow", sync)
        self.assertIn("Full-clone shadow metadata does not match", apply)
        self.assertIn("does not match the standby policy", apply)
        self.assertIn("chpasswd --encrypted", apply)
        self.assertIn('usermod --groups "$supplementary"', apply)
        self.assertIn('primary-group-names', apply)
        self.assertIn('groupadd "$group_name"', apply)
        self.assertIn('tar --numeric-owner --acls --xattrs -xzf', apply)
        self.assertNotIn('tar --no-same-owner', apply)
        self.assertIn("rm -f -- \"$archive\"", apply)
        self.assertNotIn("chpasswd --encrypted $", apply)

    def test_role_defaults_do_not_contain_real_environment_values(self):
        defaults = pathlib.Path(
            "ansible/roles/jumpserver_ha/defaults/main.yml").read_text(encoding="utf-8")
        self.assertIn("192.0.2.10", defaults)


if __name__ == "__main__":
    unittest.main()

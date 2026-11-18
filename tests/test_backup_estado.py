"""Testes estaticos do backup de estado (PC + servidor). Rodam em Linux (CI) e Windows."""
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
WB = ROOT / "workstation" / "backup"
SRV = ROOT / "ops" / "backup" / "server"
MAN = ROOT / "workstation" / "manifest" / "Export-ReinstallManifest.ps1"

SECRET_RE = re.compile(r"(AGE-SECRET-KEY-1[0-9A-Z]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|hvs\.[A-Za-z0-9_-]{20,}|nbp_[A-Za-z0-9]{20,}|gh[opsu]_[A-Za-z0-9]{30,})")


def read(p):
    return p.read_text(encoding="utf-8")


def all_files():
    return [p for d in (WB, SRV, MAN.parent) for p in d.rglob("*") if p.is_file()]


def test_files_exist():
    for p in [WB / "Invoke-StateBackup.ps1", WB / "statebackup.config.psd1", WB / "sqlite_snapshot.py", WB / "sqlite_check.py",
              WB / "Register-StateBackupTasks.ps1", SRV / "setup-statebackup.sh", SRV / "server-state-backup.sh",
              SRV / "server-state-backup.service", SRV / "server-state-backup.timer", SRV / "openbao-restore-test.sh", MAN]:
        assert p.exists(), p


def test_no_secrets_in_backup_files():
    for p in all_files():
        assert not SECRET_RE.search(read(p)), p


def test_config_scope_state_only():
    cfg = read(WB / "statebackup.config.psd1")
    for must in [r"'{HOME}\projects'", r"'{LOCALAPPDATA}\hermes'", r"'{HOME}\.codex'", r"'{HOME}\.claude'", r"'{HOME}\.gemini'",
                 r"'{APPDATA}\orca'", r"'{HOME}\.ssh'", r"'{HOME}\agent-tools'", r"'{APPDATA}\whatsapp-pessoal-mcp'",
                 r"'{APPDATA}\telegram-pessoal'"]:
        assert must in cfg, must
    includes = cfg.split("Includes = @(")[1].split(")")[0]
    for banned in ["Documents", "Downloads", "Desktop", "Videos", "Pictures"]:
        assert banned not in includes, banned
    for dep in ["'node_modules'", "'.venv'", "'__pycache__'", r"hermes\tools", r"hermes\installs", r"home\packages"]:
        assert dep in cfg, dep


def test_retention_and_freshness():
    cfg = read(WB / "statebackup.config.psd1")
    assert re.search(r"Daily\s*=\s*7;\s*Weekly\s*=\s*4;\s*Monthly\s*=\s*12", cfg)
    assert re.search(r"FreshnessHours\s*=\s*26", cfg)


def test_backup_script_never_prints_password():
    s = read(WB / "Invoke-StateBackup.ps1")
    assert "ProtectedData]::Unprotect" in s
    assert "Write-Output $env:RESTIC_PASSWORD" not in s and "Log $env:RESTIC_PASSWORD" not in s
    assert "Remove-Item Env:RESTIC_PASSWORD" in s
    for mode in ["'Init'", "'Backup'", "'Check'", "'RestoreTest'", "'Freshness'"]:
        assert mode in s


def test_tasks_wake_and_start_when_available():
    s = read(WB / "Register-StateBackupTasks.ps1")
    assert "-StartWhenAvailable" in s and "-WakeToRun:$Wake" in s and "-Wake" in s
    assert "'02:00'" in s


def test_server_user_is_restricted():
    s = read(SRV / "setup-statebackup.sh")
    assert 'restrict,from=' in s
    assert "ForceCommand internal-sftp" in s and "ChrootDirectory /srv/statebackup" in s
    assert "AllowTcpForwarding no" in s and "PermitTTY no" in s
    assert "statebackup@$PCIP" in s


def test_server_backup_encrypted_and_timer_persistent():
    s = read(SRV / "server-state-backup.sh")
    assert "age -r" in s and "docker pause" in s and "docker unpause" in s
    t = read(SRV / "server-state-backup.timer")
    assert "Persistent=true" in t and "OnCalendar=" in t


def test_restore_test_is_local_and_destroyed():
    s = read(SRV / "openbao-restore-test.sh")
    assert "127.0.0.1:$PORT:8200" in s
    assert 'docker rm -f "$NAME"' in s and "shred -u" in s and "trap cleanup EXIT" in s


@pytest.mark.skipif(shutil.which("bash") is None or not Path("/bin/bash").exists(), reason="bash indisponivel")
def test_server_scripts_bash_syntax():
    for p in SRV.glob("*.sh"):
        subprocess.run(["bash", "-n", str(p)], check=True)


def test_manifest_covers_reinstall():
    s = read(MAN)
    for k in ["winget", "scoop", "npm-global.json", "uv-tools.txt", "pyenv.txt", "nvm.txt", "clis.json", "repos.json", "scheduled-tasks.json"]:
        assert k in s, k
    for cli in ["'codex'", "'claude'", "'agy'", "'opencode'", "'orca'", "'netbird'", "'bw'", "'hermes'"]:
        assert cli in s, cli
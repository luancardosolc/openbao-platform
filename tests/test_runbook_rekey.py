"""Guarda o runbook de rekey e os helpers da estação (sem segredos, só marcadores)."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / "workstation" / "hetzner-root"
REKEY = ROOT / "ops" / "runbooks" / "rekey" / "rekey-openbao.sh"


def test_helpers_present_without_backups():
    names = {p.name for p in HELPERS.iterdir()}
    for required in ("Invoke-HetznerRoot.ps1", "Invoke-OpenBaoUnseal.ps1", "Invoke-HetznerSecretToBitwarden.ps1",
                     "Invoke-HetznerBitwardenToRemoteFile.ps1", "Invoke-LeakRedaction.ps1", "Test-NoSecrets.ps1"):
        assert required in names
    assert not [n for n in names if ".bak" in n or "_debug" in n]


def test_rekey_prints_only_markers():
    text = REKEY.read_text(encoding="utf-8")
    prints = re.findall(r'print\("([A-Z_]+)', text)
    assert set(prints) <= {"STATUS_BEFORE", "UNSEAL_OK", "REKEY_INIT_OK", "NEW_KEYS_FILE_OK", "REKEY_COMPLETE", "FAIL: "[:4]}
    assert "print(newkeys" not in text and "print(old" not in text and "print(k" not in text


def test_unseal_script_never_puts_keys_in_argv():
    text = (HELPERS / "Invoke-OpenBaoUnseal.ps1").read_text(encoding="utf-8-sig")
    assert "--data @-" in text and "shred -u" in text
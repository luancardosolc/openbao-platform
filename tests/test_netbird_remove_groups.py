"""ops/netbird/Remove-NetBirdGroups.ps1: lista explicita, checagem de referencias, protegidos, sem segredo."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOWER = (ROOT / "ops" / "netbird" / "Remove-NetBirdGroups.ps1").read_text(encoding="utf-8").lower()


def test_explicit_ids_only():
    ids = set(re.findall(r"'(dbu3[a-z0-9]{16})'", LOWER))
    assert ids == {"dbu3emitm4ms73cqtg4g", "dbu3emitm4ms73cqtg5g", "dbu3foitm4ms73cqtgdg", "dbu3foitm4ms73cqtgeg"}
    assert "'delete' \"/groups/$($t.id)\"" in LOWER
    assert LOWER.count("'delete'") == 1


def test_protected_and_reference_checks_before_delete():
    assert "'all', 'admin-pc', 'hetzner-vps'" in LOWER
    for ep in ("/policies", "/routes", "/dns/nameservers", "/dns/settings", "/setup-keys", "/users", "/posture-checks", "/networks"):
        assert f"'{ep}'" in LOWER
    assert LOWER.index("aborted: referenced") < LOWER.index("'delete'")
    assert "-checkonly" in LOWER and "group_absent" in LOWER


def test_token_stays_in_memory():
    for bad in ("write-output $script:pat", "write-host $script:pat", "set-content", "out-file", "nbp_"):
        assert bad not in LOWER
    assert "replace($script:pat, '[redacted]')" in LOWER
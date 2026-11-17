"""ops/netbird/Set-NetBirdPolicy.ps1: estatico (sem segredo, escopo certo, so marcadores)."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ops" / "netbird" / "Set-NetBirdPolicy.ps1"
TEXT = SCRIPT.read_text(encoding="utf-8")
LOWER = TEXT.lower()


def test_scope_is_pc_to_openbao_tcp_8200_one_way():
    assert "100.102.188.162" in TEXT and "100.102.58.164" in TEXT
    assert "[string]$port = '8200'" in LOWER
    assert "protocol = 'tcp'" in LOWER and "bidirectional = $false" in LOWER and "action = 'accept'" in LOWER
    assert "$sourcegroup = 'admin-pc'" in LOWER and "$destinationgroup = 'hetzner-vps'" in LOWER


def test_never_creates_or_deletes_groups_or_other_policies():
    assert not re.search(r"'(post|put|delete)'\s+'/groups", LOWER)
    assert "'delete'" not in LOWER
    assert "/policies/$($cur.id)" in LOWER  # so atualiza a policy encontrada por nome


def test_unwraps_ps51_arrays_and_checks_exact_membership():
    assert "function get-nblist" in LOWER and "foreach-object { $_ }" in LOWER
    assert "members.count -ne 1" in LOWER


def test_token_stays_in_memory():
    assert "authorization = \"token $script:pat\"" in LOWER
    for bad in ("write-output $script:pat", "write-host $script:pat", "set-content", "out-file", "-verbose", "hvs.", "nbp_"):
        assert bad not in LOWER
    assert "replace($script:pat, '[redacted]')" in LOWER
    outputs = re.findall(r"write-output\s+[\"'(]+\s*'?([a-z_]+)", LOWER)
    assert outputs and set(outputs) <= {"group_ok", "policy_created", "policy_ok", "policy_updated", "fail"}
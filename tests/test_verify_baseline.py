from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ops" / "runbooks" / "verify-baseline" / "verify-openbao-baseline.sh"
COMPOSE = ROOT / "infra" / "ansible" / "templates" / "openbao" / "docker-compose.yml.j2"


def test_script_exists_and_lf():
    data = SCRIPT.read_bytes()
    assert data.startswith(b"#!/bin/sh")
    assert b"\r\n" not in data


def test_token_never_in_argv():
    text = SCRIPT.read_text(encoding="utf-8")
    assert "-H @\"$HDR\"" in text
    assert "hvs." not in text
    assert "trap" in text and "shred -u" in text


def test_only_markers_echoed():
    for line in SCRIPT.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("echo "):
            assert s[5:].lstrip("\"").startswith(("BASELINE_", "FAIL")), s


def test_compose_has_no_bootstrap_mount():
    assert "/openbao/bootstrap" not in COMPOSE.read_text(encoding="utf-8")
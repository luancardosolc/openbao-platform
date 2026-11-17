"""Invoke-LeakRedaction.ps1: modo de valor cru via arquivo DPAPI (Windows), sem imprimir o valor."""
import json
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "workstation" / "hetzner-root" / "Invoke-LeakRedaction.ps1"

pytestmark = pytest.mark.skipif(sys.platform != "win32" or not shutil.which("powershell"), reason="DPAPI/PowerShell so no Windows")


def _ps(cmd, env=None):
    return subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
                          capture_output=True, text=True, env=env, timeout=120)


def test_static_options_present():
    text = SCRIPT.read_text(encoding="utf-8")
    assert "DpapiValueFile" in text and "ValueMode" in text and "Read-Shared" in text


def test_raw_value_redaction_from_dpapi_file(tmp_path):
    fake = "nbp_" + secrets.token_hex(18)  # valor falso, gerado no teste
    env = dict(os.environ, LEAK_FAKE=fake)
    dpapi = tmp_path / "v.dpapi"
    r = _ps("ConvertTo-SecureString $env:LEAK_FAKE -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath '%s'" % dpapi, env)
    assert r.returncode == 0, r.stderr
    logs = tmp_path / "logs"
    logs.mkdir()
    jl = logs / "s.jsonl"
    jl.write_text(json.dumps({"out": "tok=" + fake}) + "\n" + json.dumps({"x": 1}) + "\n", encoding="utf-8")
    other = logs / "a.txt"
    other.write_text("nada aqui\n", encoding="utf-8")
    base = "& '%s' -DpapiValueFile '%s' -Roots '%s' -Since '2000-01-01'" % (SCRIPT, dpapi, logs)
    r = _ps(base)
    assert "VALUES_LOADED=1 MODE=Raw" in r.stdout and "HIT exact=1" in r.stdout
    assert fake not in r.stdout + r.stderr
    r = _ps(base + " -Apply")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout and fake not in r.stdout + r.stderr
    lines = jl.read_text(encoding="utf-8").splitlines()
    assert fake not in "".join(lines) and "[REDACTED]" in lines[0]
    for line in lines:
        json.loads(line)
    assert not list(logs.glob("*.pre-redact.bak"))
    r = _ps(base)
    assert "TOTAL_EXACT_HITS=0" in r.stdout

def test_sqlite_same_length_redaction(tmp_path):
    import sqlite3
    fake = "nbp_" + secrets.token_hex(18)
    env = dict(os.environ, LEAK_FAKE=fake)
    dpapi = tmp_path / "v.dpapi"
    r = _ps("ConvertTo-SecureString $env:LEAK_FAKE -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath '%s'" % dpapi, env)
    assert r.returncode == 0, r.stderr
    logs = tmp_path / "db"
    logs.mkdir()
    db = logs / "h.sqlite"
    con = sqlite3.connect(db)
    con.execute("create table t (id integer primary key, body text)")
    con.execute("insert into t (body) values (?)", ("antes " + fake + " depois",))
    con.commit()
    con.close()
    size0 = db.stat().st_size
    r = _ps("& '%s' -DpapiValueFile '%s' -Roots '%s' -Since '2000-01-01' -Apply" % (SCRIPT, dpapi, logs))
    assert r.returncode == 0, r.stdout + r.stderr
    assert fake not in r.stdout + r.stderr
    assert db.stat().st_size == size0
    assert fake.encode() not in db.read_bytes()
    con = sqlite3.connect(db)
    assert con.execute("pragma integrity_check").fetchone()[0] == "ok"
    body = con.execute("select body from t").fetchone()[0]
    con.close()
    assert body.startswith("antes [REDACTED") and body.endswith("] depois") and len(body) == len("antes  depois") + len(fake)
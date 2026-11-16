#!/usr/bin/env python3
"""Read-only health snapshot for the existing Hetzner host.

This intentionally uses an unprivileged SSH account and never executes package,
service, firewall, Docker mutation, or reboot commands.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable


REMOTE_PROBE = r'''set +e
printf 'host|'; hostname 2>/dev/null
printf 'os|'; . /etc/os-release; printf '%s|%s\n' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-unknown}"
printf 'uptime|'; uptime -p 2>/dev/null
printf 'load|'; awk '{print $1 "," $2 "," $3}' /proc/loadavg 2>/dev/null
printf 'cpus|'; nproc 2>/dev/null
printf 'memory|'; awk '/MemTotal:/{t=$2}/MemAvailable:/{a=$2}END{printf "%s|%s\n",t,a}' /proc/meminfo 2>/dev/null
printf 'disk|'; df -Pk / | awk 'NR==2{printf "%s|%s|%s|%s\n",$2,$3,$4,$5}'
if test -e /var/run/reboot-required; then echo 'reboot|required'; else echo 'reboot|not-required'; fi
for unit in docker netbird ssh unattended-upgrades cloud-init-hotplugd; do
  state=$(systemctl is-active "$unit" 2>/dev/null || true)
  printf 'unit|%s|%s\n' "$unit" "${state:-unknown}"
done
printf 'failed_units|'; systemctl --failed --no-legend --plain 2>/dev/null | awk '{printf "%s ",$1}END{print ""}'
printf 'docker_api|'; if docker ps >/dev/null 2>&1; then echo 'accessible'; else echo 'permission-denied'; fi
printf 'openbao_health|'; curl -k -sS --max-time 4 -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8200/v1/sys/health 2>/dev/null || echo 'unreachable'
'''


def ssh_argv(host: str, user: str, key_path: str, ssh: str = "ssh") -> list[str]:
    """Build an SSH invocation pinned to the user's known_hosts file."""
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", host):
        raise ValueError("host must be a hostname or IP address")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", user):
        raise ValueError("user must be a simple SSH account name")
    if not key_path:
        raise ValueError("key path is required (set HETZNER_SSH_KEY)")
    return [
        ssh,
        "-F", "NUL" if os.name == "nt" else "/dev/null",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "IdentitiesOnly=yes",
        "-i", str(Path(key_path).expanduser()),
        f"{user}@{host}",
        "bash", "-s",
    ]


def parse_probe(raw: str) -> dict:
    result: dict = {"units": {}}
    for line in raw.splitlines():
        parts = line.split("|")
        key = parts[0]
        if key == "unit" and len(parts) >= 3:
            result["units"][parts[1]] = parts[2]
        elif key == "failed_units":
            result["failed_units"] = parts[1].split() if len(parts) > 1 and parts[1].strip() else []
        elif key == "memory" and len(parts) >= 3:
            result["memory_kib"] = {"total": _int(parts[1]), "available": _int(parts[2])}
        elif key == "disk" and len(parts) >= 5:
            result["root_disk_kib"] = {
                "total": _int(parts[1]), "used": _int(parts[2]),
                "available": _int(parts[3]), "use_percent": _percent(parts[4]),
            }
        elif key == "load" and len(parts) > 1:
            result["load_average"] = parts[1]
        elif key == "cpus" and len(parts) > 1:
            result["cpu_count"] = _int(parts[1])
        elif key == "os" and len(parts) >= 3:
            result["os"] = {"name": parts[1], "version": parts[2]}
        elif len(parts) > 1:
            result[key] = parts[1]
    return result


def _int(value: str) -> int | None:
    try:
        return int(value)
    except ValueError:
        return None


def _percent(value: str) -> int | None:
    return _int(value.rstrip("%"))


def assess(data: dict) -> list[dict[str, str]]:
    """Return explicit findings; unknown privileged state is never called OK."""
    checks: list[dict[str, str]] = []
    reboot = data.get("reboot")
    checks.append({"name": "reboot", "status": "warning" if reboot == "required" else "ok" if reboot == "not-required" else "unknown", "detail": str(reboot or "not measured")})

    failed = data.get("failed_units", [])
    checks.append({"name": "systemd_failed_units", "status": "warning" if failed else "ok" if "failed_units" in data else "unknown", "detail": ", ".join(failed) if failed else "none" if "failed_units" in data else "not measured"})

    for unit in ("docker", "netbird", "ssh", "unattended-upgrades"):
        state = data.get("units", {}).get(unit)
        checks.append({"name": f"unit:{unit}", "status": "ok" if state == "active" else "critical" if state in {"failed", "inactive"} else "unknown", "detail": str(state or "not measured")})

    docker_api = data.get("docker_api")
    checks.append({"name": "docker_inventory", "status": "ok" if docker_api == "accessible" else "unknown", "detail": "accessible" if docker_api == "accessible" else "permission denied; container/app state unverified" if docker_api == "permission-denied" else "not measured"})

    bao = data.get("openbao_health")
    checks.append({"name": "openbao_http", "status": "ok" if bao == "200" else "critical" if bao in {"000", "unreachable"} else "warning" if bao else "unknown", "detail": str(bao or "not measured")})
    dashboard = data.get("netbird_dashboard")
    checks.append({"name": "netbird_dashboard", "status": "ok" if dashboard == "200" else "critical" if dashboard in {"000", "unreachable"} or (dashboard and dashboard.startswith("5")) else "warning" if dashboard else "unknown", "detail": str(dashboard or "not measured")})
    disk = data.get("root_disk_kib", {}).get("use_percent")
    if disk is not None:
        checks.append({"name": "root_disk", "status": "critical" if disk >= 95 else "warning" if disk >= 85 else "ok", "detail": f"{disk}% used"})
    memory = data.get("memory_kib", {})
    if memory.get("total") and memory.get("available") is not None:
        available_percent = round(memory["available"] * 100 / memory["total"])
        checks.append({"name": "memory_available", "status": "critical" if available_percent <= 5 else "warning" if available_percent <= 10 else "ok", "detail": f"{available_percent}% available"})
    load = data.get("load_average")
    cpus = data.get("cpu_count")
    if load and cpus:
        try:
            load_5m = float(load.split(",")[1])
            checks.append({"name": "load_5m", "status": "critical" if load_5m >= cpus * 4 else "warning" if load_5m >= cpus * 2 else "ok", "detail": f"{load_5m:.2f} / {cpus} vCPU"})
        except (ValueError, IndexError):
            checks.append({"name": "load_5m", "status": "unknown", "detail": "malformed load average"})
    return checks


def probe_https(url: str, timeout: float = 5) -> str:
    """Return the HTTP status for a public HTTPS endpoint without credentials."""
    request = urllib.request.Request(url, headers={"User-Agent": "hetzner-health/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return str(response.status)
    except urllib.error.HTTPError as exc:
        return str(exc.code)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return "unreachable"


def run_probe(argv: list[str], runner: Callable = subprocess.run) -> tuple[int, str, str]:
    # Windows checkouts use CRLF; Bash on the remote Linux host treats stray CR
    # bytes as part of tokens and paths, so normalize the script before sending.
    script = REMOTE_PROBE.replace("\r\n", "\n").replace("\r", "").encode("utf-8")
    completed = runner(argv, input=script, capture_output=True, timeout=25, check=False)
    return completed.returncode, completed.stdout.decode("utf-8", "replace"), completed.stderr.decode("utf-8", "replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.environ.get("HETZNER_HOST", "100.102.58.164"))
    parser.add_argument("--user", default=os.environ.get("HETZNER_USER", "luan"))
    parser.add_argument("--ssh-key", default=os.environ.get("HETZNER_SSH_KEY", ""), help="private key path; never printed or copied")
    parser.add_argument("--dashboard-url", default=os.environ.get("HETZNER_NETBIRD_URL", "https://46.224.228.253.sslip.io/"))
    parser.add_argument("--output", type=Path, help="optional JSON report path")
    parser.add_argument("--json", action="store_true", help="print full JSON")
    args = parser.parse_args()
    try:
        ssh = shutil.which("ssh.exe") or shutil.which("ssh")
        if not ssh and os.name == "nt":
            windows = Path(os.environ.get("WINDIR", r"C:\Windows"))
            # Sysnative bypasses System32 redirection when Python is 32-bit.
            candidates = [windows / "Sysnative" / "OpenSSH" / "ssh.exe", windows / "System32" / "OpenSSH" / "ssh.exe"]
            ssh = next((str(path) for path in candidates if path.exists()), None)
        if not ssh:
            raise FileNotFoundError("OpenSSH client was not found")
        argv = ssh_argv(args.host, args.user, args.ssh_key, ssh)
        rc, stdout, stderr = run_probe(argv)
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"SSH probe could not run: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    if rc:
        # SSH diagnostics may contain paths; never echo arbitrary remote output.
        print(f"SSH probe failed (exit {rc}); verify NetBird connectivity, key agent, and known_hosts.", file=sys.stderr)
        return 2

    data = parse_probe(stdout)
    report = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "target": {"host": args.host, "user": args.user},
        "source": "unprivileged SSH; no remote changes",
        "host": data,
        "external": {"netbird_dashboard_http": probe_https(args.dashboard_url)},
        "stderr_present": bool(stderr.strip()),
    }
    data["netbird_dashboard"] = report["external"]["netbird_dashboard_http"]
    report["checks"] = assess(data)
    serialized = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    if args.json:
        print(serialized, end="")
    else:
        print(f"Hetzner health · {report['generated_at_utc']} · {args.host}")
        for check in report["checks"]:
            print(f"{check['status'].upper():8} {check['name']}: {check['detail']}")
        print("Cobertura: leitura sem sudo; containers e estado interno do NetBird permanecem não verificados.")
    return 1 if any(c["status"] == "critical" for c in report["checks"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())

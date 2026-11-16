#!/usr/bin/env python3
"""Compare two JSON health snapshots and flag new health/resource regressions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def _float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _load_5m(host: dict) -> float | None:
    try:
        return float(host.get("load_average", "").split(",")[1])
    except (ValueError, IndexError):
        return None


def _memory_available_percent(host: dict) -> float | None:
    memory = host.get("memory_kib", {})
    total, available = _float(memory.get("total")), _float(memory.get("available"))
    return available * 100 / total if total and available is not None else None


def compare(before: dict, after: dict, *, max_load_increase: float = 1.0,
            max_memory_drop_pp: float = 15.0, max_disk_growth_pp: float = 10.0) -> dict:
    old_checks = {c["name"]: c["status"] for c in before.get("checks", [])}
    new_checks = {c["name"]: c["status"] for c in after.get("checks", [])}
    regressions = []
    for name, status in new_checks.items():
        previous = old_checks.get(name, "unknown")
        if status == "critical" and previous != "critical":
            regressions.append(f"check {name}: {previous} -> critical")
        elif status == "warning" and previous not in {"warning", "critical"}:
            regressions.append(f"check {name}: {previous} -> warning")
        elif status == "unknown" and previous == "ok":
            regressions.append(f"check {name}: ok -> unknown")

    old_host, new_host = before.get("host", {}), after.get("host", {})
    old_load, new_load = _load_5m(old_host), _load_5m(new_host)
    old_mem, new_mem = _memory_available_percent(old_host), _memory_available_percent(new_host)
    old_disk = _float(old_host.get("root_disk_kib", {}).get("use_percent"))
    new_disk = _float(new_host.get("root_disk_kib", {}).get("use_percent"))
    delta = {}
    for key, old, new, limit, label in (
        ("load_5m", old_load, new_load, max_load_increase, "load média de 5 min"),
        ("memory_available_percent", old_mem, new_mem, max_memory_drop_pp, "memória disponível (p.p.)"),
        ("root_disk_use_percent", old_disk, new_disk, max_disk_growth_pp, "uso do disco raiz (p.p.)"),
    ):
        if old is None or new is None:
            delta[key] = None
            continue
        change = new - old
        delta[key] = round(change, 2)
        worsening = -change if key == "memory_available_percent" else change
        if worsening > limit:
            regressions.append(f"{label} piorou {worsening:.2f}, limite {limit:.2f}")

    return {"result": "review" if regressions else "no_regression_detected",
            "deltas": delta, "regressions": regressions}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--max-load-increase", type=float, default=1.0)
    parser.add_argument("--max-memory-drop-pp", type=float, default=15.0)
    parser.add_argument("--max-disk-growth-pp", type=float, default=10.0)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        before = json.loads(args.before.read_text(encoding="utf-8"))
        after = json.loads(args.after.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"could not read snapshots: {type(exc).__name__}", file=sys.stderr)
        return 2
    result = compare(before, after, max_load_increase=args.max_load_increase,
                     max_memory_drop_pp=args.max_memory_drop_pp,
                     max_disk_growth_pp=args.max_disk_growth_pp)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(result["result"])
        for issue in result["regressions"]:
            print(f"- {issue}")
        print("A ausência de regressões nestas métricas não substitui testes funcionais de cada aplicação.")
    return 1 if result["regressions"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

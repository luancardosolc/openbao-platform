#!/usr/bin/env python3
"""Copias consistentes (API de backup do SQLite) de todos os bancos dentro das pastas do backup de estado.

uso: sqlite_snapshot.py --config statebackup.resolved.json --out <pasta>
Grava <out>/<C>/<caminho>/<arquivo> e <out>/sqlite-snapshots.json. Imprime so um resumo (sem conteudo).
"""
import argparse, json, os, sqlite3, sys, time

EXTS = (".db", ".sqlite", ".sqlite3")
MAGIC = b"SQLite format 3\x00"

def excluded(path, name, names, paths):
    if name.lower() in names:
        return True
    p = os.path.normcase(os.path.normpath(path))
    return any(p == x or p.startswith(x + os.sep) for x in paths)

def is_sqlite(p):
    try:
        with open(p, "rb") as f:
            return f.read(16) == MAGIC
    except OSError:
        return False

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cfg = json.load(open(a.config, encoding="utf-8-sig"))
    names = {n.lower() for n in cfg["exclude_names"]}
    paths = [os.path.normcase(os.path.normpath(p)) for p in cfg["exclude_paths"]]
    ok, failed, skipped_big = [], [], []
    t0 = time.time()
    for root in cfg["includes"]:
        if not os.path.exists(root):
            continue
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if not excluded(os.path.join(dp, d), d, names, paths)]
            for fn in fns:
                if not fn.lower().endswith(EXTS):
                    continue
                src = os.path.join(dp, fn)
                if excluded(src, fn, names, paths) or not is_sqlite(src):
                    continue
                drive, rest = os.path.splitdrive(src)
                dst = os.path.join(a.out, drive.rstrip(":"), rest.lstrip("\\/"))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                try:
                    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True, timeout=30)
                    d = sqlite3.connect(dst)
                    with d:
                        s.backup(d)
                    r = d.execute("PRAGMA quick_check").fetchone()[0]
                    d.close(); s.close()
                    (ok if r == "ok" else failed).append({"path": src, "check": r})
                except Exception as e:
                    failed.append({"path": src, "error": type(e).__name__})
                    try:
                        os.remove(dst)
                    except OSError:
                        pass
    summary = {"ok": len(ok), "failed": failed, "seconds": round(time.time() - t0, 1), "files": [x["path"] for x in ok]}
    json.dump(summary, open(os.path.join(a.out, "sqlite-snapshots.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps({"sqlite_ok": len(ok), "sqlite_failed": len(failed), "seconds": summary["seconds"]}))
    return 0

if __name__ == "__main__":
    sys.exit(main())
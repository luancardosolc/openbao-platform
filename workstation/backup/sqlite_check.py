#!/usr/bin/env python3
"""PRAGMA integrity_check + numero de tabelas de um SQLite restaurado. Imprime: '<resultado> <tabelas>'."""
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
r = c.execute("PRAGMA integrity_check").fetchone()[0]
n = c.execute("select count(*) from sqlite_master where type='table'").fetchone()[0]
print(r, n)
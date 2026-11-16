#!/usr/bin/env python3
# Forwards stdin to a child after stripping a leading UTF-8 BOM
# (PowerShell 5.1 Process.StandardInput injects one).
# argv: <timeout_sec> <exe> [args...]
import os, sys, subprocess

def main():
    if len(sys.argv) < 3:
        sys.stderr.write("run-capture: usage: timeout exe [args...]\n")
        return 2
    try:
        timeout = int(sys.argv[1])
    except ValueError:
        timeout = 60
    exe = sys.argv[2]
    args = sys.argv[3:]
    data = sys.stdin.buffer.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        p = subprocess.run(
            [exe] + args,
            input=data if data else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        sys.stderr.write("run-capture: timeout\n")
        return 3
    except Exception as e:
        sys.stderr.write("run-capture: %s\n" % e)
        return 2
    sys.stdout.buffer.write(p.stdout or b"")
    sys.stderr.buffer.write(p.stderr or b"")
    return p.returncode

if __name__ == "__main__":
    sys.exit(main())

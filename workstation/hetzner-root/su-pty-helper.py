import os, pty, select, sys, time, errno

def scrub(s, pw):
    if pw:
        s = s.replace(pw, "[REDACTED]")
    lines = []
    for line in s.splitlines():
        low = line.lower()
        if "password:" in low and "REDACTED" not in line:
            lines.append("[password-prompt]")
        else:
            lines.append(line)
    return "\n".join(lines)

def read_remaining(fd, buf, timeout=0.8):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        end = time.time() + 0.3
    return buf

def reap(pid, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            wpid, st = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return 0
        if wpid == pid:
            if hasattr(os, "waitstatus_to_exitcode"):
                return os.waitstatus_to_exitcode(st)
            return (st >> 8)
        time.sleep(0.05)
    try:
        os.kill(pid, 15)
    except Exception:
        pass
    time.sleep(0.2)
    try:
        wpid, st = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            if hasattr(os, "waitstatus_to_exitcode"):
                return os.waitstatus_to_exitcode(st)
            return (st >> 8)
    except ChildProcessError:
        return 0
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except Exception:
        pass
    return 3

def main():
    if len(sys.argv) < 2:
        print("SU_ERR=missing_script", flush=True)
        return 2
    script = sys.argv[1]
    timeout = 170
    if len(sys.argv) >= 3:
        try:
            timeout = int(sys.argv[2])
        except ValueError:
            timeout = 170
    raw = sys.stdin.buffer.readline()
    if raw.startswith(bytes([239, 187, 191])):
        raw = raw[3:]
    pw = raw.decode("utf-8", "replace").rstrip("\r\n").lstrip("\ufeff")
    if not pw:
        print("SU_ERR=empty_password", flush=True)
        return 2
    try:
        os.set_blocking(sys.stdin.fileno(), False)
        while sys.stdin.read(4096):
            pass
    except Exception:
        pass

    cmd = "bash -- " + script
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("su", ["su", "-c", cmd])
        os._exit(127)

    buf = b""
    sent = False
    deadline = time.time() + max(5, timeout)
    status_rc = None
    eof = False
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError as e:
                if e.errno == errno.EIO:
                    eof = True
                    chunk = b""
                else:
                    raise
            if not chunk:
                eof = True
            else:
                buf += chunk
                if (not sent) and (b"assword:" in buf.lower()):
                    os.write(fd, (pw + "\n").encode("utf-8"))
                    sent = True
        try:
            wpid, st = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                if hasattr(os, "waitstatus_to_exitcode"):
                    status_rc = os.waitstatus_to_exitcode(st)
                else:
                    status_rc = (st >> 8)
                buf = read_remaining(fd, buf)
                break
        except ChildProcessError:
            if status_rc is None:
                status_rc = 0
            break
        if eof and status_rc is None:
            buf = read_remaining(fd, buf)
            status_rc = reap(pid, timeout=3)
            break

    out = scrub(buf.decode("utf-8", "replace"), pw)
    if status_rc is None:
        print("SU_ERR=timeout_or_hang", flush=True)
        print(out, flush=True)
        reap(pid, timeout=2)
        try:
            os.close(fd)
        except Exception:
            pass
        return 3
    try:
        os.close(fd)
    except Exception:
        pass
    print(out, flush=True)
    return 0 if status_rc == 0 else status_rc

if __name__ == "__main__":
    sys.exit(main())

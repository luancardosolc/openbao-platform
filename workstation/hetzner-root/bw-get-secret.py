#!/usr/bin/env python3
# Read a Bitwarden item (notes or first attachment) to stdout as raw bytes.
# Never prints to stderr except FAIL. Used only by the restore script.
import json, os, shutil, subprocess, sys, tempfile

def fail(msg):
    sys.stderr.write("FAIL\n")
    if msg:
        sys.stderr.write(msg + "\n")
    sys.exit(1)

def bw(args, timeout=90):
    env = os.environ.copy()
    if not env.get("BW_SESSION"):
        fail("missing BW_SESSION")
    p = subprocess.run(["bw"] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, env=env)
    return p.returncode, p.stdout, p.stderr

def bw_json(args, timeout=90):
    rc, out, err = bw(args, timeout=timeout)
    if rc != 0:
        fail("bw command failed")
    return json.loads(out.decode("utf-8"))

def find_folder_id(name):
    for f in bw_json(["list", "folders"]):
        if (f.get("name") or "") == name:
            return f.get("id")
    fail("folder not found")

def find_item(name, folder_id):
    items = bw_json(["list", "items", "--search", name], timeout=120)
    matches = [it for it in items if (it.get("name") or "") == name and (not folder_id or (it.get("folderId") or "") == folder_id)]
    if not matches:
        fail("item not found")
    if len(matches) > 1:
        fail("multiple items with the same name")
    return matches[0]

def shred_path(path):
    if not path or not os.path.exists(path):
        return
    try:
        size = os.path.getsize(path)
        with open(path, "wb") as f:
            f.write(b"\x00" * max(32, min(size, 1_000_000)))
            f.flush()
            os.fsync(f.fileno())
    except Exception:
        pass
    try:
        os.remove(path)
    except Exception:
        pass

def main(argv):
    name = None
    folder = "Hetzner"
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--name" and i + 1 < len(argv):
            name = argv[i + 1]; i += 2
        elif a == "--folder" and i + 1 < len(argv):
            folder = argv[i + 1]; i += 2
        else:
            fail("invalid arguments")
    if not name:
        fail("missing --name")
    folder_id = find_folder_id(folder)
    item = find_item(name, folder_id)
    atts = item.get("attachments") or []
    data = None
    if atts:
        att_id = atts[0].get("id")
        tmpdir = tempfile.mkdtemp(prefix="bw-hz-g-")
        dest = os.path.join(tmpdir, "got.bin")
        try:
            rc, out, err = bw(["get", "attachment", att_id, "--itemid", item["id"], "--output", dest], timeout=90)
            if rc != 0 or not os.path.exists(dest):
                fail("bw get attachment failed")
            with open(dest, "rb") as f:
                data = f.read()
        finally:
            shred_path(dest)
            shutil.rmtree(tmpdir, ignore_errors=True)
    if data is None:
        notes = item.get("notes") or ""
        if not notes or notes.startswith("Payload stored as attachment only"):
            fail("item has no payload")
        data = notes.encode("utf-8")
    sys.stdout.buffer.write(data)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception:
        fail("unexpected error")

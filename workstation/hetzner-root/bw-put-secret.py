#!/usr/bin/env python3
# Read secret bytes from stdin (BOM-stripped). Create or update a Bitwarden
# Secure Note in a folder, optional attachment, sync, verify SHA-256.
# Prints ONLY: ITEM, BYTES, SHA256_PREFIX, OK/FAIL. Never prints payload.
import hashlib, json, os, shutil, subprocess, sys, tempfile, time

def fail(msg):
    sys.stdout.write("FAIL\n")
    # msg must not include payload
    if msg:
        sys.stderr.write(msg + "\n")
    sys.exit(1)

def strip_bom(b):
    if b.startswith(b"\xef\xbb\xbf"):
        return b[3:]
    return b

def bw(args, stdin=None, timeout=90):
    env = os.environ.copy()
    if not env.get("BW_SESSION"):
        fail("missing BW_SESSION")
    p = subprocess.run(
        ["bw"] + args,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
    )
    return p.returncode, p.stdout, p.stderr

def bw_json(args, timeout=90):
    rc, out, err = bw(args, timeout=timeout)
    if rc != 0:
        fail("bw command failed")
    try:
        return json.loads(out.decode("utf-8"))
    except Exception:
        fail("bw returned invalid json")

def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()

def find_folder_id(name):
    folders = bw_json(["list", "folders"])
    for f in folders:
        if (f.get("name") or "") == name:
            return f.get("id")
    fail("folder not found")

def find_item(name, folder_id):
    items = bw_json(["list", "items", "--search", name], timeout=120)
    matches = []
    for it in items:
        if (it.get("name") or "") != name:
            continue
        fid = it.get("folderId") or ""
        if folder_id:
            if fid == folder_id:
                matches.append(it)
        else:
            matches.append(it)
    if len(matches) > 1:
        fail("multiple items with the same name in the folder")
    return matches[0] if matches else None

def encode_item(obj):
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    rc, out, err = bw(["encode"], stdin=raw, timeout=60)
    if rc != 0 or not out.strip():
        fail("bw encode failed")
    return out.strip()

def notes_from_bytes(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if "\x00" in text:
        return None
    # Bitwarden notes are typically capped; keep a conservative limit
    if len(text) > 9000:
        return None
    return text

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

def restrict_acl(path):
    # Best-effort: on Windows lock down the temp file to the current user
    if os.name != "nt":
        try:
            os.chmod(path, 0o600)
        except Exception:
            pass
        return
    user = os.environ.get("USERNAME") or ""
    if not user:
        return
    subprocess.run(
        ["icacls", path, "/inheritance:r", "/grant:r", user + ":F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

def main(argv):
    # args: --name NAME --folder FOLDER [--attachment-name NAME]
    name = None
    folder = "Hetzner"
    att_name = "payload.bin"
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--name" and i + 1 < len(argv):
            name = argv[i + 1]; i += 2
        elif a == "--folder" and i + 1 < len(argv):
            folder = argv[i + 1]; i += 2
        elif a == "--attachment-name" and i + 1 < len(argv):
            att_name = argv[i + 1]; i += 2
        else:
            fail("invalid arguments")
    if not name:
        fail("missing --name")
    data = strip_bom(sys.stdin.buffer.read())
    if not data:
        fail("empty payload")
    digest = sha256_hex(data)
    folder_id = find_folder_id(folder)
    existing = find_item(name, folder_id)
    notes = notes_from_bytes(data)
    if existing:
        item = existing
        item["notes"] = notes if notes is not None else (
            "Payload stored as attachment only. BYTES=%d SHA256_PREFIX=%s" % (len(data), digest[:8])
        )
        item["folderId"] = folder_id
        if item.get("type") != 2:
            # keep type if already a secure note; otherwise still edit notes
            pass
        enc = encode_item(item)
        rc, out, err = bw(["edit", "item", item["id"]], stdin=enc, timeout=90)
        if rc != 0:
            fail("bw edit item failed")
        item = json.loads(out.decode("utf-8"))
    else:
        item = {
            "type": 2,
            "name": name,
            "notes": notes if notes is not None else (
                "Payload stored as attachment only. BYTES=%d SHA256_PREFIX=%s" % (len(data), digest[:8])
            ),
            "folderId": folder_id,
            "secureNote": {"type": 0},
        }
        enc = encode_item(item)
        rc, out, err = bw(["create", "item"], stdin=enc, timeout=90)
        if rc != 0:
            fail("bw create item failed")
        item = json.loads(out.decode("utf-8"))
    item_id = item.get("id")
    if not item_id:
        fail("item id missing after save")

    # replace attachments with a single fresh one
    for att in list(item.get("attachments") or []):
        att_id = att.get("id")
        if att_id:
            bw(["delete", "attachment", att_id, "--itemid", item_id], timeout=60)

    tmpdir = tempfile.mkdtemp(prefix="bw-hz-")
    tmpfile = os.path.join(tmpdir, att_name)
    try:
        with open(tmpfile, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        restrict_acl(tmpfile)
        rc, out, err = bw(
            ["create", "attachment", "--itemid", item_id, "--file", tmpfile],
            timeout=90,
        )
        attachment_ok = (rc == 0)
    finally:
        shred_path(tmpfile)
        try:
            shutil.rmtree(tmpdir, ignore_errors=True)
        except Exception:
            pass

    rc, out, err = bw(["sync"], timeout=120)
    if rc != 0:
        fail("bw sync failed")

    # verify notes and/or attachment
    got = bw_json(["get", "item", item_id], timeout=60)
    verified = False
    if notes is not None:
        got_notes = got.get("notes") or ""
        if sha256_hex(got_notes.encode("utf-8")) == digest:
            verified = True
    atts = got.get("attachments") or []
    if atts and not verified:
        att_id = atts[0].get("id")
        # download to a temp and hash
        tmpdir = tempfile.mkdtemp(prefix="bw-hz-v-")
        dest = os.path.join(tmpdir, "got.bin")
        try:
            rc, out, err = bw(
                ["get", "attachment", att_id, "--itemid", item_id, "--output", dest],
                timeout=90,
            )
            if rc != 0 or not os.path.exists(dest):
                fail("bw get attachment failed")
            with open(dest, "rb") as f:
                got_bytes = f.read()
            if sha256_hex(got_bytes) == digest:
                verified = True
        finally:
            shred_path(dest)
            try:
                shutil.rmtree(tmpdir, ignore_errors=True)
            except Exception:
                pass

    if not verified:
        fail("hash mismatch after sync")
    # Attachment is best-effort: some plans reject attachments; notes already verified.

    sys.stdout.write("ITEM=%s\n" % name)
    sys.stdout.write("BYTES=%d\n" % len(data))
    sys.stdout.write("SHA256_PREFIX=%s\n" % digest[:8])
    sys.stdout.write("OK\n")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception:
        fail("unexpected error")

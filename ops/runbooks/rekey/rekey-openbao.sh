#!/bin/sh
# Rekey do OpenBao: unseal (se selado) com as chaves atuais e rekey para 5 novas (t=3), tudo no servidor.
# Executado em 16/11/2026 (versao com SRC=bootstrap.json). Parametros: SRC, RESOLVE, ORIGEM (env).
# Chaves nunca vão para stdout. Saída: só metadados.
set -eu
umask 077
W=/root/openbao-rekey-work
mkdir -p "$W"; chmod 700 "$W"
python3 - <<'PY'
import json, os, subprocess, sys

W = "/root/openbao-rekey-work"
CA = "/opt/openbao/tls/openbao.crt"
SRC = os.environ.get("SRC", "/root/hzroot-unseal.json")  # 15/11: /opt/openbao/bootstrap/bootstrap.json (apagado)
ADDR = "https://46.224.228.253:8200"
RESOLVE = os.environ.get("RESOLVE", "46.224.228.253:8200:100.102.58.164")  # 15/11: ...:127.0.0.1 (antes do bind na VPN)

def api(method, path, body=None):
    cmd = ["curl", "-s", "-S", "-o", os.path.join(W, "resp.json"), "-w", "%{http_code}",
           "--cacert", CA, "--resolve", RESOLVE, "-X", method, ADDR + path]
    if body is not None:
        bp = os.path.join(W, "body.json")
        with open(bp, "w") as f:
            json.dump(body, f)
        os.chmod(bp, 0o600)
        cmd += ["-H", "Content-Type: application/json", "--data-binary", "@" + bp]
    code = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    try:
        bp = os.path.join(W, "body.json")
        if os.path.exists(bp):
            os.remove(bp)
    except OSError:
        pass
    with open(os.path.join(W, "resp.json")) as f:
        data = json.load(f) if os.path.getsize(os.path.join(W, "resp.json")) else {}
    return int(code or 0), data

with open(SRC) as f:
    boot = json.load(f)
old = list(boot.get("unseal_keys_b64") or boot.get("keys_base64") or [])
threshold = int(boot.get("unseal_threshold") or boot.get("threshold"))
if len(old) < threshold:
    print("FAIL: chaves insuficientes no bootstrap"); sys.exit(2)

code, st = api("GET", "/v1/sys/seal-status")
print("STATUS_BEFORE http=%s sealed=%s t=%s n=%s" % (code, st.get("sealed"), st.get("t"), st.get("n")))

r = st
for k in (old[:threshold] if st.get("sealed") else []):
    code, r = api("PUT", "/v1/sys/unseal", {"key": k})
    if code != 200:
        print("FAIL: unseal http=%s" % code); sys.exit(3)
    if not r.get("sealed", True):
        break
if r.get("sealed", True):
    print("FAIL: continua selado após unseal"); sys.exit(3)
print("UNSEAL_OK")

code, init = api("PUT", "/v1/sys/rekey/init", {"secret_shares": 5, "secret_threshold": 3})
if code != 200 or not init.get("nonce"):
    print("FAIL: rekey init http=%s" % code); sys.exit(4)
nonce = init["nonce"]
print("REKEY_INIT_OK shares=5 threshold=3")

out = None
for k in old[:threshold]:
    code, out = api("PUT", "/v1/sys/rekey/update", {"key": k, "nonce": nonce})
    if code != 200:
        print("FAIL: rekey update http=%s" % code); sys.exit(5)
    if out.get("complete"):
        break
if not out or not out.get("complete"):
    print("FAIL: rekey não completou"); sys.exit(5)

newkeys = out.get("keys_base64") or []
if len(newkeys) != 5:
    print("FAIL: esperado 5 chaves novas, recebido %d" % len(newkeys)); sys.exit(6)
dest = os.path.join(W, "new-keys.json")
with open(dest, "w") as f:
    json.dump({"keys_base64": newkeys, "keys": out.get("keys", []), "threshold": 3, "shares": 5,
               "origem": os.environ.get("ORIGEM", "rekey")}, f)
os.chmod(dest, 0o600)
print("NEW_KEYS_FILE_OK count=%d bytes=%d" % (len(newkeys), os.path.getsize(dest)))
print("REKEY_COMPLETE")
PY

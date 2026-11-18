#!/usr/bin/env bash
# Teste de restore do OpenBao num container temporario so em 127.0.0.1, depois destruido.
# Uso (root): openbao-restore-test.sh <arquivo.tar.zst.age> <age_identity_file> <unseal_json> <root_token_file>
# Imprime so linhas RT_*. Nunca imprime chaves/token. Apaga tudo no final (trap).
set -euo pipefail
ART="$1"; IDF="$2"; KEYS="$3"; TOKF="$4"
NAME=openbao-restore-test; PORT=18200
W=$(mktemp -d /root/bao-rt.XXXXXX)
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$W"; for f in "$IDF" "$KEYS" "$TOKF"; do [ -e "$f" ] && shred -u "$f"; done; echo "RT_CLEANUP ok container_gone=$([ -z "$(docker ps -aq -f name=^$NAME$)" ] && echo yes || echo no)"; }
trap cleanup EXIT
age -d -i "$IDF" -o "$W/s.tar.zst" "$ART"
zstd -q -d "$W/s.tar.zst" -o "$W/s.tar"
echo "RT_TAR_SHA256 $(sha256sum "$W/s.tar" | cut -c1-16)"
mkdir -p "$W/root"; tar -C "$W/root" -xf "$W/s.tar" opt/openbao
D="$W/root/opt/openbao"
echo "RT_FILES $(find "$D/data" -type f | wc -l)"
cat > "$W/test.hcl" <<'EOF'
ui = false
disable_mlock = true
storage "file" { path = "/openbao/file" }
listener "tcp" { address = "0.0.0.0:8200" tls_disable = true }
api_addr = "http://127.0.0.1:8200"
EOF
IMG=$(docker inspect openbao --format '{{.Config.Image}}')
chown -R 100:1000 "$D/data" 2>/dev/null || true
docker run -d --name "$NAME" --cap-add IPC_LOCK -p 127.0.0.1:$PORT:8200 -v "$D/data:/openbao/file" -v "$W/test.hcl:/openbao/config/test.hcl:ro" "$IMG" server -config=/openbao/config/test.hcl >/dev/null
A="http://127.0.0.1:$PORT"
i=0; until c=$(curl -s -o /dev/null -w '%{http_code}' "$A/v1/sys/health"); [ "$c" = 503 ] || [ "$c" = 200 ] || [ "$c" = 501 ]; do i=$((i+1)); [ $i -ge 60 ] && { echo "RT_FAIL api code=$c"; docker logs --tail 20 "$NAME" 2>&1 | sed 's/^/RT_LOG /'; exit 4; }; sleep 1; done
echo "RT_BEFORE sealed=$(curl -s "$A/v1/sys/seal-status" | jq -r .sealed) init=$(curl -s "$A/v1/sys/seal-status" | jq -r .initialized)"
T=$(jq -r .threshold "$KEYS"); n=0
while [ $n -lt "$T" ]; do jq -c "{key: .keys_base64[$n]}" "$KEYS" | curl -s -X PUT --data @- "$A/v1/sys/unseal" | jq -r '"RT_STEP sealed=\(.sealed) progress=\(.progress)/\(.t)"'; n=$((n+1)); done
S=$(curl -s "$A/v1/sys/seal-status" | jq -r .sealed); H=$(curl -s -o /dev/null -w '%{http_code}' "$A/v1/sys/health")
echo "RT_UNSEALED sealed=$S health=$H"
TOKV=$(jq -r '.root_token // .token // empty' "$TOKF" 2>/dev/null || true); [ -n "$TOKV" ] || TOKV=$(tr -d '\r\n' < "$TOKF")
LOOK=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $TOKV" "$A/v1/auth/token/lookup-self")
MOUNTS=$(curl -s -H "X-Vault-Token: $TOKV" "$A/v1/sys/mounts" | jq -r '.data // . | keys | map(select(endswith("/"))) | join(",")')
POL=$(curl -s -H "X-Vault-Token: $TOKV" "$A/v1/sys/policies/acl?list=true" | jq -r '.data.keys | length')
echo "RT_ROOT_LOOKUP http=$LOOK"; echo "RT_MOUNTS $MOUNTS"; echo "RT_POLICIES count=$POL"
unset TOKV
[ "$S" = false ] && [ "$H" = 200 ] && [ "$LOOK" = 200 ] && echo "RT_OK" || { echo "RT_FAIL"; exit 5; }
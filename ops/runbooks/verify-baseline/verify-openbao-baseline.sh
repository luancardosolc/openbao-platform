#!/bin/sh
# Confere o baseline do OpenBao prod imprimindo so marcadores BASELINE_* (sem segredos).
# Uso: rodar como root via Invoke-HetznerRoot.ps1 -MarkersOnly -MarkerPattern '^(BASELINE_|FAIL)' -ScriptFile <este arquivo>
# Pre-requisito: TOKFILE (padrao /root/hzroot-root.tok) gravado pelo Invoke-HetznerBitwardenToRemoteFile.ps1
#   a partir do item Bitwarden 'OpenBao prod / root token (AAAA-MM-DD)' (JSON com root_token).
# O token nunca vai para argv: vira um arquivo de header (modo 600) usado com curl -H @arquivo. trap EXIT faz shred.
A=${A:-https://100.102.58.164:8200}
TOKFILE=${TOKFILE:-/root/hzroot-root.tok}
EXP_MOUNTS=${EXP_MOUNTS:-cubbyhole,identity,kv,sys}
EXP_POLICIES=${EXP_POLICIES:-5}
EXP_KV=${EXP_KV:-3}
HDR=$(mktemp /root/hzroot-hdr.XXXXXX)
trap 'shred -u "$HDR" 2>/dev/null; if [ -e "$TOKFILE" ]; then shred -u "$TOKFILE" && echo "BASELINE_SHRED ok" || echo "BASELINE_SHRED FAIL"; else echo "BASELINE_SHRED ok(absent)"; fi' EXIT
chmod 600 "$HDR"
[ -s "$TOKFILE" ] || { echo "FAIL tokfile missing"; exit 3; }
printf 'X-Vault-Token: %s\n' "$(jq -r .root_token "$TOKFILE")" > "$HDR"
S=$(curl -sk "$A/v1/sys/seal-status" | jq -r .sealed)
H=$(curl -sk -o /dev/null -w '%{http_code}' "$A/v1/sys/health")
echo "BASELINE_SEAL sealed=$S health=$H"
L=$(curl -sk -o /dev/null -w '%{http_code}' -H @"$HDR" "$A/v1/auth/token/lookup-self")
echo "BASELINE_TOKEN lookup_self=$L"
M=$(curl -sk -H @"$HDR" "$A/v1/sys/mounts" | jq -r '.data // . | keys[] | select(endswith("/")) | rtrimstr("/")' | sort | paste -sd, -)
echo "BASELINE_MOUNTS $M"
P=$(curl -sk -H @"$HDR" "$A/v1/sys/policies/acl?list=true" | jq -r '.data.keys | length')
PN=$(curl -sk -H @"$HDR" "$A/v1/sys/policies/acl?list=true" | jq -r '.data.keys | sort | join(",")')
echo "BASELINE_POLICIES count=$P names=$PN"
K=$(curl -sk -X LIST -H @"$HDR" "$A/v1/kv/metadata/" | jq -r '.data.keys | length')
echo "BASELINE_KV keys=$K"
if [ "$S" = false ] && [ "$H" = 200 ] && [ "$L" = 200 ] && [ "$M" = "$EXP_MOUNTS" ] && [ "$P" = "$EXP_POLICIES" ] && [ "$K" = "$EXP_KV" ]; then
  echo "BASELINE_OK"
else
  echo "FAIL baseline mismatch"; exit 5
fi
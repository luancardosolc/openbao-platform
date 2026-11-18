#!/usr/bin/env bash
# Backup noturno do estado do servidor (OpenBao + NetBird + configs) -> tar.zst cifrado com age.
# Saida: /srv/statebackup/server-state/server-state-<UTC>.tar.zst.age (+ .sha256, latest.json)
# O PC puxa via SFTP (usuario restrito statebackup, so pela NetBird) e guarda no restic.
# Consistencia: docker pause (congela sem selar o OpenBao) durante o tar, que leva segundos.
set -euo pipefail
umask 027
OUT=/srv/statebackup/server-state
CONF=/etc/server-state-backup
KEEP=${KEEP:-3}
REC_FILE="$CONF/age-recipient.txt"
TS=$(date -u +%Y%m%dT%H%M%SZ)
NAME="server-state-$TS.tar.zst.age"
PAUSED=()
WORK=$(mktemp -d /root/ssb.XXXXXX)
cleanup() { for c in "${PAUSED[@]:-}"; do [ -n "$c" ] && docker unpause "$c" >/dev/null 2>&1 || true; done; rm -rf "$WORK"; }
trap cleanup EXIT
[ -s "$REC_FILE" ] || { echo "SSB_FAIL no recipient"; exit 2; }
command -v age >/dev/null || { echo "SSB_FAIL age missing"; exit 2; }
mkdir -p "$OUT"
PATHS=(opt/openbao opt/netbird etc/server-state-backup etc/ssh/sshd_config etc/ssh/sshd_config.d etc/ssh/authorized_keys etc/systemd/system/server-state-backup.service etc/systemd/system/server-state-backup.timer etc/ufw home/luan/backups)
for v in netbird_netbird_data netbird_netbird_traefik_letsencrypt; do
  mp=$(docker volume inspect "$v" --format '{{.Mountpoint}}' 2>/dev/null || true)
  [ -n "$mp" ] && PATHS+=("${mp#/}")
done
EXIST=(); for p in "${PATHS[@]}"; do [ -e "/$p" ] && EXIST+=("$p"); done
for c in openbao netbird-server; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ]; then docker pause "$c" >/dev/null && PAUSED+=("$c"); fi
done
T0=$(date +%s.%N)
tar -C / --numeric-owner -cf "$WORK/state.tar" "${EXIST[@]}"
for c in "${PAUSED[@]:-}"; do [ -n "$c" ] && docker unpause "$c" >/dev/null; done; PAUSED=()
T1=$(date +%s.%N)
zstd -q -19 -T0 "$WORK/state.tar" -o "$WORK/state.tar.zst"
age -r "$(head -n1 "$REC_FILE")" -o "$WORK/$NAME" "$WORK/state.tar.zst"
SHA=$(sha256sum "$WORK/$NAME" | cut -d' ' -f1)
TARSHA=$(sha256sum "$WORK/state.tar" | cut -d' ' -f1)
install -o root -g statebackup -m 640 "$WORK/$NAME" "$OUT/$NAME"
echo "$SHA  $NAME" > "$OUT/$NAME.sha256"; chown root:statebackup "$OUT/$NAME.sha256"; chmod 640 "$OUT/$NAME.sha256"
SIZE=$(stat -c %s "$OUT/$NAME")
printf '{"ts":"%s","file":"%s","sha256":"%s","tar_sha256":"%s","bytes":%s,"pause_seconds":%s,"paths":%s}\n' \
  "$TS" "$NAME" "$SHA" "$TARSHA" "$SIZE" "$(echo "$T1 - $T0" | bc 2>/dev/null || echo 0)" "$(printf '%s\n' "${EXIST[@]}" | jq -R . | jq -sc .)" > "$OUT/latest.json"
chown root:statebackup "$OUT/latest.json"; chmod 640 "$OUT/latest.json"
ls -1t "$OUT"/server-state-*.tar.zst.age 2>/dev/null | tail -n +$((KEEP+1)) | while read -r f; do rm -f -- "$f" "$f.sha256"; done
echo "SSB_OK file=$NAME bytes=$SIZE sha256=${SHA:0:12}"
#!/usr/bin/env bash
# Idempotente. Rodar como root. Cria o usuario SFTP restrito "statebackup" (chroot, so SFTP, so do IP NetBird do PC),
# instala age, o script/units do backup do servidor e o recipient age (chave publica; a identidade fica no Bitwarden).
# Uso: setup-statebackup.sh <pc_netbird_ip> <ssh_pubkey_line> <age_recipient>
set -euo pipefail
PCIP="$1"; PUB="$2"; REC="$3"
[[ "$PCIP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "SETUP_FAIL bad ip"; exit 2; }
[[ "$PUB" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+ ]] || { echo "SETUP_FAIL bad pubkey"; exit 2; }
[[ "$REC" =~ ^age1[0-9a-z]+$ ]] || { echo "SETUP_FAIL bad recipient"; exit 2; }
command -v age >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq age sqlite3 bc >/dev/null
id statebackup >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /srv/statebackup --shell /usr/sbin/nologin statebackup
passwd -l statebackup >/dev/null 2>&1 || true
install -d -o root -g root -m 755 /srv/statebackup
install -d -o statebackup -g statebackup -m 700 /srv/statebackup/restic
install -d -o root -g statebackup -m 750 /srv/statebackup/server-state
install -d -o root -g root -m 755 /etc/ssh/authorized_keys
printf 'restrict,from="%s" %s\n' "$PCIP" "$PUB" > /etc/ssh/authorized_keys/statebackup
chown root:root /etc/ssh/authorized_keys/statebackup; chmod 644 /etc/ssh/authorized_keys/statebackup
cat > /etc/ssh/sshd_config.d/60-statebackup.conf <<'EOF'
# Backup do PC (restic via SFTP). So chroot + internal-sftp, sem shell, sem forwarding.
Match User statebackup
    AuthorizedKeysFile /etc/ssh/authorized_keys/statebackup
    ChrootDirectory /srv/statebackup
    ForceCommand internal-sftp -d /restic
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PermitTunnel no
EOF
chmod 644 /etc/ssh/sshd_config.d/60-statebackup.conf
if ! grep -qE "^AllowUsers .*statebackup@$PCIP" /etc/ssh/sshd_config; then
  cp -p /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak-$(date -u +%Y%m%dT%H%M%SZ)"
  sed -i -E "s/^(AllowUsers .*)$/\1 statebackup@$PCIP/" /etc/ssh/sshd_config
fi
sshd -t && systemctl reload ssh
install -d -o root -g root -m 755 /etc/server-state-backup
echo "$REC" > /etc/server-state-backup/age-recipient.txt; chmod 644 /etc/server-state-backup/age-recipient.txt
echo "SETUP_OK user=statebackup allow=$PCIP"
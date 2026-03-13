# Operational Runbook

## Scope

This runbook captures the most common day-2 operations for a single-node OpenBao deployment managed by this repository.

## Environment

Set the target endpoint first:

```bash
export BAO_ADDR="https://YOUR_OPENBAO_HOST:8200"
export BAO_SKIP_VERIFY=true
```

If you are using the bootstrap artifact locally:

```bash
export BAO_TOKEN="$(jq -r '.root_token' ./bootstrap.json)"
```

## Service Health

```bash
curl -k -sS "${BAO_ADDR}/v1/sys/health" | jq
bao status -format=json | jq '{initialized, sealed, version}'
```

## Seal and Unseal

Seal the instance:

```bash
bao operator seal
```

Unseal the instance with three keys:

```bash
bao operator unseal "$(jq -r '.unseal_keys_b64[0]' ./bootstrap.json)"
bao operator unseal "$(jq -r '.unseal_keys_b64[1]' ./bootstrap.json)"
bao operator unseal "$(jq -r '.unseal_keys_b64[2]' ./bootstrap.json)"
```

## Policies

List policies:

```bash
bao policy list
```

Read the platform admin policy:

```bash
bao policy read platform-admin
```

Write or update a policy:

```bash
bao policy write my-policy ./my-policy.hcl
```

## Tokens

Create an operator token:

```bash
bao token create -policy=platform-admin -display-name=platform-operator
```

Revoke a token:

```bash
bao token revoke TOKEN_VALUE
```

## KV Secrets

List mounts:

```bash
bao secrets list
```

Write a secret:

```bash
bao kv put kv/example username=admin password=change-me
```

Read a secret:

```bash
bao kv get kv/example
```

Delete a secret:

```bash
bao kv delete kv/example
```

## Logs

Inspect container logs:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@YOUR_SERVER_IP 'sudo docker logs --tail 200 openbao'
```

Inspect the audit log:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@YOUR_SERVER_IP 'sudo tail -n 200 /opt/openbao/logs/audit.log'
```

## Restart the Service

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@YOUR_SERVER_IP \
  'cd /opt/openbao && sudo docker compose up -d'
```

After a restart, recheck health and unseal if needed.

## Backup

Run a local encrypted backup on the host:

```bash
export BACKUP_PASSPHRASE='strong-passphrase'
make backup
```

## Restore

Restore from an encrypted archive:

```bash
export BACKUP_PASSPHRASE='strong-passphrase'
make restore ARCHIVE=./backups/openbao-YYYYMMDDHHMMSS.tar.gz.enc
```

After restore:

1. Recheck service health.
2. Unseal the instance if necessary.
3. Run `make smoke` or the equivalent smoke validation.

## Post-Deploy Smoke

```bash
export OPENBAO_ADDR="https://YOUR_OPENBAO_HOST:8200"
export OPENBAO_SKIP_VERIFY=true
export OPENBAO_TOKEN="$(jq -r '.root_token' ./bootstrap.json)"

make smoke
```

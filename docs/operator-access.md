# Operator Access

## Purpose

This document describes how an operator retrieves bootstrap artifacts, logs into OpenBao for the first time, and moves from bootstrap credentials to a safer day-2 operating model.

## Preconditions

- The deployment has completed successfully.
- You have SSH access to the target host.
- You know the OpenBao endpoint.
- You have the passphrase used to encrypt the bootstrap artifact.

## Bootstrap Artifact Locations

The deployment writes bootstrap outputs on the host under:

- `/opt/openbao/bootstrap/bootstrap.json`
- `/opt/openbao/bootstrap/bootstrap.json.enc`

The plaintext `bootstrap.json` is useful for initial recovery and automation checks, but it should not be treated as long-term operator storage. The encrypted `.enc` file is the portable artifact.

## Retrieve the Encrypted Bootstrap Artifact

Copy the encrypted file from the server to your local workstation:

```bash
scp -i ~/.ssh/id_ed25519 \
  ubuntu@YOUR_SERVER_IP:/opt/openbao/bootstrap/bootstrap.json.enc \
  ./bootstrap.json.enc
```

Decrypt it locally:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in ./bootstrap.json.enc \
  -out ./bootstrap.json
```

Inspect the bootstrap payload:

```bash
jq '{root_token, unseal_keys_b64}' ./bootstrap.json
```

## First Login

Open the UI:

```text
https://YOUR_OPENBAO_HOST:8200/ui/
```

If the environment still uses a self-signed certificate, your browser will show a trust warning. That is expected until the production TLS task is completed.

Choose `Token` as the auth method and sign in with the `root_token` from `bootstrap.json`.

## CLI Login

Use the CLI with TLS verification disabled only when the deployment still uses the self-signed bootstrap certificate:

```bash
export BAO_ADDR="https://YOUR_OPENBAO_HOST:8200"
export BAO_SKIP_VERIFY=true
export BAO_TOKEN="$(jq -r '.root_token' ./bootstrap.json)"

bao status
bao secrets list
bao policy list
```

## Immediate Post-Login Tasks

After the first successful login, do these before treating the platform as operational:

1. Confirm the instance is initialized and unsealed.
2. Confirm the `kv/` secrets engine exists.
3. Confirm the `platform-admin` policy exists.
4. Move the encrypted bootstrap artifact to a secure operator-controlled location.
5. Remove plaintext bootstrap material from transient local directories.
6. Plan the root-token rotation task from Trello before routine usage begins.

## Minimal Validation Commands

```bash
bao status -format=json | jq '{initialized, sealed, version}'
bao secrets list -format=json | jq 'keys'
bao policy read platform-admin
```

## Root Token Handling

The bootstrap root token is a break-glass credential, not the desired long-term operator credential.

Recommended handling:

- Use it only for initial validation and admin bootstrap.
- Store it in an operator-controlled secure location.
- Prefer creating scoped admin tokens for regular work.
- Keep unseal keys separate from the root token.
- Treat the plaintext `bootstrap.json` as temporary working material.

## Suggested Next Hardening Step

Create a dedicated operational admin token after login:

```bash
bao token create -policy=platform-admin -display-name=platform-admin-operator
```

Store that new token securely, validate it, and then stop using the bootstrap root token for routine operations.

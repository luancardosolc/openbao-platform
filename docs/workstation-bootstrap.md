# Workstation Bootstrap

## Purpose

This document describes how OpenBao is now used as the first real workstation secret store for rebuilding a Codex-enabled operator machine.

The goal is to make a new laptop or desktop reproducible without relying on memory, scattered shell exports, or plaintext notes.

## Scope

OpenBao now stores workstation bootstrap data for:

- Codex and MCP metadata
- GitHub MCP personal token
- GitHub MCP client token
- Postman MCP token
- Trello MCP credentials
- SSH metadata and alias conventions

It does not automatically replace interactive sign-in where a tool is designed around re-authentication, such as Codex local auth state.

## Current Secret Paths

The following KV v2 paths are in use:

- `kv/workstation/mcp/github-personal`
- `kv/workstation/mcp/github-client`
- `kv/workstation/mcp/postman`
- `kv/workstation/mcp/trello`
- `kv/workstation/ssh/metadata`
- `kv/workstation/codex/metadata`

## Data Model

### GitHub MCP secrets

Each GitHub path stores:

- `token`
- `env_var`
- `provider`
- `account_scope`

### Postman MCP secret

The Postman path stores:

- `token`
- `env_var`
- `provider`

### Trello MCP secret

The Trello path stores:

- `api_key`
- `token`
- `env_vars`
- `provider`
- `storage_model`

### SSH metadata

The SSH metadata path stores:

- `config_path`
- `key_names`
- `aliases`

### Codex metadata

The Codex metadata path stores:

- `config_path`
- `auth_path`
- `mcp_servers`
- `note`

The `note` field explicitly documents that `~/.codex/auth.json` should not be copied blindly across machines. Codex itself should be re-authenticated on a new machine unless you intentionally design a different secret-handling model.

## Reading the Secrets

The simplest operator flow is:

1. Connect to the NetBird VPN.
2. Export `OPENBAO_ADDR`.
3. Export a valid `OPENBAO_TOKEN`.
4. Read the workstation paths you need.

Example:

```bash
export OPENBAO_ADDR="https://10.100.33.16:8200"
export OPENBAO_TOKEN="..."
export OPENBAO_SKIP_VERIFY=true

curl -ksS \
  -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
  "${OPENBAO_ADDR}/v1/kv/data/workstation/mcp/github-personal"
```

## Helper Script

This repository now provides a simple helper:

```bash
./scripts/export-workstation-secrets.sh github-personal
./scripts/export-workstation-secrets.sh github-client
./scripts/export-workstation-secrets.sh postman
./scripts/export-workstation-secrets.sh trello
./scripts/export-workstation-secrets.sh ssh-metadata
./scripts/export-workstation-secrets.sh codex-metadata
```

The script prints shell-friendly exports for single-env-var secret paths, prints both Trello exports together, and pretty JSON for metadata paths.

## Recommended Local Runtime Pattern

For Codex workstation bootstrap, keep OpenBao as the source of truth and use small local files only as runtime inputs for shell startup.

Current pattern on the reference Mac:

- `~/.config/codex/github_pat_pessoal`
- `~/.config/codex/github_pat_cliente`
- `~/.config/codex/github_env.sh`
- `~/.config/codex/trello_api_key`
- `~/.config/codex/trello_token`
- `~/.config/codex/trello_env.sh`

The shell loads these with:

- `source ~/.config/codex/github_env.sh`
- `[ -f ~/.config/codex/trello_env.sh ] && source ~/.config/codex/trello_env.sh`

This keeps `~/.codex/config.toml` free of inline Trello credentials while preserving a simple startup flow for Codex and MCP servers.

## Cross-Platform Recovery

When rebuilding on another machine:

1. Clone the required repositories into the local projects root for that OS.
2. Restore SSH config and aliases.
3. Install NetBird and connect to the VPN.
4. Read workstation metadata and secrets from OpenBao.
5. Recreate `~/.codex/config.toml` and MCP-related environment variables.
6. Re-authenticate Codex if needed.

Recommended logical roots:

- macOS: `~/projects`
- Linux: `~/projects`
- Windows: `C:\projects`

The logical layout should remain stable even if the absolute path changes by OS.

## Safety Rules

- Do not store plaintext secrets in Trello.
- Do not store plaintext secrets in Obsidian notes.
- Do not copy private SSH keys into OpenBao casually without a deliberate key-management decision.
- Treat OpenBao as the source of truth for workstation tokens, not as a dumping ground for every local file.

# Changelog

## 2026-11-16 (BRT)
- `workstation/hetzner-root/`: helpers PowerShell de acesso root no Hetzner (su via PTY, saída redigida ou só marcadores), envio de segredos servidor ⇄ Bitwarden, unseal determinístico (`Invoke-OpenBaoUnseal.ps1`), redação de vazamentos locais (`Invoke-LeakRedaction.ps1`) e varredura de segredos (`Test-NoSecrets.ps1`). Vieram de `C:\Users\luanc\agent-tools\hetzner-root`, que segue como cópia de execução.
- `ops/runbooks/rekey/`: runbook e `rekey-openbao.sh` parametrizado.
- `openspec/changes/openbao-remediacao/` e `docs/pareceres/` (prompt-02, prompt-03, execução e parecer): vieram de `conectores/whatsapp-business-mcp`.
- `.gitignore`: padrões de segredos (`*.dpapi`, `.env*`, `bootstrap*.json`, `*-keys*.json`, `hzroot-*`).
- `tests/test_runbook_rekey.py`.
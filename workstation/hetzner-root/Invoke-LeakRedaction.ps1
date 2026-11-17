<#
Invoke-LeakRedaction.ps1 - redige valores vazados (lidos do Bitwarden SO em memoria) em logs locais.
Nunca imprime valores nem trechos: so caminho, contagens e OK/FAIL.
Uso:
  $env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
  .\Invoke-LeakRedaction.ps1 -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)' -Roots C:\Users\luanc\.claude -Since '2026-11-15 18:00'          # so conta
  .\Invoke-LeakRedaction.ps1 ... -Apply [-GenericFiles <arquivos>]   # redige (copia .pre-redact.bak, troca atomica, verifica, zera e apaga o .bak)
Binarios .sqlite/.db: troca de mesmo tamanho (-SameLengthExt). Tolerante a valores com espaco/\n/ANSI entre caracteres. Leitura/escrita em Latin1 (bytes preservados 1:1).
Valor cru (2026-11-17), para tokens que nao sao JSON (ex. PAT do NetBird):
  .\Invoke-LeakRedaction.ps1 -ItemName 'NetBird / API token owner (AAAA-MM-DD)' -ValueMode Raw -Roots ... [-Apply]   # notes inteiras = 1 valor
  .\Invoke-LeakRedaction.ps1 -DpapiValueFile <arquivo> -Roots ... [-Apply]   # arquivo de ConvertFrom-SecureString (DPAPI do usuario); util quando o item ja foi trocado
Arquivos travados por outro processo sao lidos com FileShare.ReadWrite.
#>
param(
  [string]$ItemName,
  [ValidateSet('Json','Raw')][string]$ValueMode = 'Json',
  [string]$DpapiValueFile,
  [int]$MinValues = -1,
  [Parameter(Mandatory)][string[]]$Roots,
  [datetime]$Since = '2026-11-15 18:00',
  [switch]$Apply,
  [string[]]$GenericFiles = @(),
  [string[]]$ApplyExt = @('.jsonl','.json','.txt','.md','.log','.ndjson','.out'),
  # binarios (ex. SQLite): troca cada ocorrencia por texto do MESMO tamanho, preservando offsets/paginas; confira com PRAGMA integrity_check
  [string[]]$SameLengthExt = @('.sqlite','.db')
)
$ErrorActionPreference = 'Stop'
$vals = New-Object System.Collections.Generic.List[string]
function Walk($o, $k) {
  if ($null -eq $o) { return }
  if ($o -is [string]) { if ($o.Length -ge 16 -and $k -match 'key|token|recovery') { $vals.Add($o) } ; return }
  if ($o -is [System.Collections.IEnumerable] -and -not ($o -is [string])) { foreach ($x in $o) { Walk $x $k }; return }
  if ($o -is [psobject]) { foreach ($p in $o.PSObject.Properties) { Walk $p.Value $p.Name } }
}
if ($DpapiValueFile) {
  $ValueMode = 'Raw'
  $sec = ConvertTo-SecureString ((Get-Content -LiteralPath $DpapiValueFile -Raw).Trim())
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $raw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  if ($raw.Trim().Length -ge 16) { $vals.Add($raw.Trim()) }
  $raw = $null
} elseif ($ItemName) {
  if (-not $env:BW_SESSION) { throw 'BW_SESSION vazio' }
  $items = (& bw list items --search $ItemName --session $env:BW_SESSION 2>$null) | ConvertFrom-Json
  $item = @($items | Where-Object { $_.name -eq $ItemName })
  if ($item.Count -ne 1) { Write-Output "FAIL item_count=$($item.Count)"; exit 2 }
  $notes = [string]$item[0].notes
  if ($ValueMode -eq 'Raw') { if ($notes.Trim().Length -ge 16) { $vals.Add($notes.Trim()) } }
  else { Walk ($notes | ConvertFrom-Json) '' }
  $notes = $null; $item = $null; $items = $null
} else { Write-Output 'FAIL need -ItemName or -DpapiValueFile'; exit 2 }
if ($MinValues -lt 0) { $MinValues = if ($ValueMode -eq 'Raw') { 1 } else { 6 } }
$vals = @($vals | Sort-Object -Unique | Sort-Object Length -Descending)
Write-Output "VALUES_LOADED=$($vals.Count) MODE=$ValueMode"
if ($vals.Count -lt $MinValues) { Write-Output 'FAIL too_few_values'; exit 2 }
function Read-Shared([string]$path) {
  $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite,Delete')
  try { $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); return ,$ms.ToArray() } finally { $fs.Close() }
}
$sep = '(?:\s|\\[nrt]|\x1b\[[0-9;?]*[A-Za-z]|\\u001b\[[0-9;?]*[A-Za-z])*'
$alts = foreach ($v in $vals) { ($v.ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }) -join $sep }
$rxExact = [regex]::new('(?:' + ($alts -join '|') + ')', 'Compiled')
$rxGeneric = [regex]::new('(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])|(?<![0-9a-fA-F])(?:[0-9a-fA-F]{66}|[0-9a-fA-F]{64})(?![0-9a-fA-F])|(?<![A-Za-z0-9])(?:hv)?s\.[A-Za-z0-9]{20,}|("(?:unseal_keys_b64|unseal_keys_hex|root_token|recovery_keys_b64|recovery_keys_hex|recovery_keys)\\?"\s*:\s*)(\[[^\]]*\]|\\?"[^"\\]*\\?")', 'Compiled')
$lat = [System.Text.Encoding]::GetEncoding(28591)
$genericSet = @{}; foreach ($g in $GenericFiles) { $genericSet[(Resolve-Path $g).Path.ToLower()] = $true }
$files = foreach ($r in $Roots) { if (Test-Path $r) { Get-ChildItem $r -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since -and $_.Length -lt 300MB -and $_.FullName -notlike '*.pre-redact.bak' } } }
$totalHits = 0; $fail = 0
foreach ($f in $files) {
  try { $bytes = Read-Shared $f.FullName } catch { continue }
  $txt = $lat.GetString($bytes)
  $isGen = $genericSet.ContainsKey($f.FullName.ToLower())
  $n = $rxExact.Matches($txt).Count
  $g = if ($isGen) { $rxGeneric.Matches($txt).Count } else { 0 }
  if ($n -eq 0 -and $g -eq 0) { continue }
  $totalHits += $n
  $ext = $f.Extension.ToLower()
  $line = "HIT exact=$n generic=$g ext=$ext path=$($f.FullName)"
  if (-not $Apply) { Write-Output $line; continue }
  $same = $SameLengthExt -contains $ext
  if (-not $same -and $ApplyExt -notcontains $ext) { Write-Output "$line SKIP(binary/ext)"; continue }
  $p = $f.FullName; $bak = "$p.pre-redact.bak"; $tmp = "$p.redact.tmp"
  [IO.File]::WriteAllBytes($bak, (Read-Shared $p))
  $ok = $false
  for ($try = 0; $try -lt 5 -and -not $ok; $try++) {
    $len0 = (Get-Item -LiteralPath $p).Length
    $bytes = Read-Shared $p; $txt = $lat.GetString($bytes)
    if ($same) { $new = $rxExact.Replace($txt, { param($m) $L = $m.Value.Length; if ($L -ge 10) { '[REDACTED' + ('X' * ($L - 10)) + ']' } else { 'X' * $L } }) } else { $new = $rxExact.Replace($txt, '[REDACTED]') }
    if ($isGen) { $new = $rxGeneric.Replace($new, { param($m) if ($m.Groups[1].Success) { $m.Groups[1].Value + '"[REDACTED]"' } else { '[REDACTED]' } }) }
    [IO.File]::WriteAllBytes($tmp, $lat.GetBytes($new))
    if ((Get-Item -LiteralPath $p).Length -ne $len0) { Remove-Item $tmp -Force; Start-Sleep -Milliseconds 300; continue }
    # SQLite/binario: sempre reescreve no lugar (o processo dono mantem o mesmo arquivo aberto)
    try { if ($same) { throw 'in-place' }; Move-Item -LiteralPath $tmp -Destination $p -Force; $ok = $true }
    catch {
      # arquivo aberto sem FILE_SHARE_DELETE: reescreve no lugar
      try { $fs = [IO.File]::Open($p, 'Open', 'ReadWrite', 'ReadWrite'); $nb = [IO.File]::ReadAllBytes($tmp); $fs.SetLength(0); $fs.Write($nb,0,$nb.Length); $fs.Close(); Remove-Item $tmp -Force; $ok = $true } catch { if ($fs) { $fs.Close() } }
    }
  }
  $after = $lat.GetString((Read-Shared $p))
  $n2 = $rxExact.Matches($after).Count; $g2 = if ($isGen) { $rxGeneric.Matches($after).Count } else { 0 }
  # generic: o campo redigido ainda casa o grupo de campo; conta so os que nao sao [REDACTED]
  if ($isGen) { $g2 = @($rxGeneric.Matches($after) | Where-Object { $_.Value -notmatch 'REDACTED' }).Count }
  $parseBad = 0
  if ($ext -eq '.jsonl') { foreach ($l in ($after -split "`n")) { if ($l.Trim()) { try { $null = $l | ConvertFrom-Json -ErrorAction Stop } catch { $parseBad++ } } } }
  if ($ok -and $n2 -eq 0 -and $g2 -eq 0 -and $parseBad -eq 0) {
    $z = New-Object byte[] ((Get-Item -LiteralPath $bak).Length); [IO.File]::WriteAllBytes($bak, $z); Remove-Item -LiteralPath $bak -Force
    Write-Output "$line -> after exact=$n2 generic=$g2 jsonl_bad_lines=$parseBad OK"
  } else { $fail++; Write-Output "$line -> after exact=$n2 generic=$g2 jsonl_bad_lines=$parseBad replaced=$ok FAIL (backup mantido: $bak)" }
}
Write-Output "TOTAL_EXACT_HITS=$totalHits FAILS=$fail"
if ($fail) { exit 1 }
<#
Invoke-LeakRedaction.ps1 - redige valores vazados (lidos do Bitwarden SO em memoria) em logs locais.
Nunca imprime valores nem trechos: so caminho, contagens e OK/FAIL.
Uso:
  $env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
  .\Invoke-LeakRedaction.ps1 -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)' -Roots C:\Users\luanc\.claude -Since '2026-11-15 18:00'          # so conta
  .\Invoke-LeakRedaction.ps1 ... -Apply [-GenericFiles <arquivos>]   # redige (copia .pre-redact.bak, troca atomica, verifica, zera e apaga o .bak)
Tolerante a valores com espaco/\n/ANSI entre caracteres. Leitura/escrita em Latin1 (bytes preservados 1:1).
#>
param(
  [Parameter(Mandatory)][string]$ItemName,
  [Parameter(Mandatory)][string[]]$Roots,
  [datetime]$Since = '2026-11-15 18:00',
  [switch]$Apply,
  [string[]]$GenericFiles = @(),
  [string[]]$ApplyExt = @('.jsonl','.json','.txt','.md','.log','.ndjson','.out')
)
$ErrorActionPreference = 'Stop'
if (-not $env:BW_SESSION) { throw 'BW_SESSION vazio' }
$items = (& bw list items --search $ItemName --session $env:BW_SESSION 2>$null) | ConvertFrom-Json
$item = @($items | Where-Object { $_.name -eq $ItemName })
if ($item.Count -ne 1) { Write-Output "FAIL item_count=$($item.Count)"; exit 2 }
$notes = $item[0].notes
$obj = $notes | ConvertFrom-Json
$vals = New-Object System.Collections.Generic.List[string]
function Walk($o, $k) {
  if ($null -eq $o) { return }
  if ($o -is [string]) { if ($o.Length -ge 16 -and $k -match 'key|token|recovery') { $vals.Add($o) } ; return }
  if ($o -is [System.Collections.IEnumerable] -and -not ($o -is [string])) { foreach ($x in $o) { Walk $x $k }; return }
  if ($o -is [psobject]) { foreach ($p in $o.PSObject.Properties) { Walk $p.Value $p.Name } }
}
Walk $obj ''
$vals = @($vals | Sort-Object -Unique | Sort-Object Length -Descending)
Write-Output "VALUES_LOADED=$($vals.Count)"
if ($vals.Count -lt 6) { Write-Output 'FAIL too_few_values'; exit 2 }
$sep = '(?:\s|\\[nrt]|\x1b\[[0-9;?]*[A-Za-z]|\\u001b\[[0-9;?]*[A-Za-z])*'
$alts = foreach ($v in $vals) { ($v.ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }) -join $sep }
$rxExact = [regex]::new('(?:' + ($alts -join '|') + ')', 'Compiled')
$rxGeneric = [regex]::new('(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])|(?<![0-9a-fA-F])(?:[0-9a-fA-F]{66}|[0-9a-fA-F]{64})(?![0-9a-fA-F])|(?<![A-Za-z0-9])(?:hv)?s\.[A-Za-z0-9]{20,}|("(?:unseal_keys_b64|unseal_keys_hex|root_token|recovery_keys_b64|recovery_keys_hex|recovery_keys)\\?"\s*:\s*)(\[[^\]]*\]|\\?"[^"\\]*\\?")', 'Compiled')
$lat = [System.Text.Encoding]::GetEncoding(28591)
$genericSet = @{}; foreach ($g in $GenericFiles) { $genericSet[(Resolve-Path $g).Path.ToLower()] = $true }
$files = foreach ($r in $Roots) { if (Test-Path $r) { Get-ChildItem $r -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since -and $_.Length -lt 300MB -and $_.FullName -notlike '*.pre-redact.bak' } } }
$totalHits = 0; $fail = 0
foreach ($f in $files) {
  try { $bytes = [IO.File]::ReadAllBytes($f.FullName) } catch { continue }
  $txt = $lat.GetString($bytes)
  $isGen = $genericSet.ContainsKey($f.FullName.ToLower())
  $n = $rxExact.Matches($txt).Count
  $g = if ($isGen) { $rxGeneric.Matches($txt).Count } else { 0 }
  if ($n -eq 0 -and $g -eq 0) { continue }
  $totalHits += $n
  $ext = $f.Extension.ToLower()
  $line = "HIT exact=$n generic=$g ext=$ext path=$($f.FullName)"
  if (-not $Apply) { Write-Output $line; continue }
  if ($ApplyExt -notcontains $ext) { Write-Output "$line SKIP(binary/ext)"; continue }
  $p = $f.FullName; $bak = "$p.pre-redact.bak"; $tmp = "$p.redact.tmp"
  Copy-Item -LiteralPath $p -Destination $bak -Force
  $ok = $false
  for ($try = 0; $try -lt 5 -and -not $ok; $try++) {
    $len0 = (Get-Item -LiteralPath $p).Length
    $bytes = [IO.File]::ReadAllBytes($p); $txt = $lat.GetString($bytes)
    $new = $rxExact.Replace($txt, '[REDACTED]')
    if ($isGen) { $new = $rxGeneric.Replace($new, { param($m) if ($m.Groups[1].Success) { $m.Groups[1].Value + '"[REDACTED]"' } else { '[REDACTED]' } }) }
    [IO.File]::WriteAllBytes($tmp, $lat.GetBytes($new))
    if ((Get-Item -LiteralPath $p).Length -ne $len0) { Remove-Item $tmp -Force; Start-Sleep -Milliseconds 300; continue }
    try { Move-Item -LiteralPath $tmp -Destination $p -Force; $ok = $true }
    catch {
      # arquivo aberto sem FILE_SHARE_DELETE: reescreve no lugar
      try { $fs = [IO.File]::Open($p, 'Open', 'ReadWrite', 'ReadWrite'); $nb = [IO.File]::ReadAllBytes($tmp); $fs.SetLength(0); $fs.Write($nb,0,$nb.Length); $fs.Close(); Remove-Item $tmp -Force; $ok = $true } catch { if ($fs) { $fs.Close() } }
    }
  }
  $after = $lat.GetString([IO.File]::ReadAllBytes($p))
  $n2 = $rxExact.Matches($after).Count; $g2 = if ($isGen) { $rxGeneric.Matches($after).Count } else { 0 }
  # generic: o campo redigido ainda casa o grupo de campo; conta so os que nao sao [REDACTED]
  if ($isGen) { $g2 = @($rxGeneric.Matches($after) | Where-Object { $_.Value -notmatch 'REDACTED' }).Count }
  $parseBad = 0
  if ($ext -eq '.jsonl') { foreach ($l in [IO.File]::ReadAllLines($p)) { if ($l.Trim()) { try { $null = $l | ConvertFrom-Json -ErrorAction Stop } catch { $parseBad++ } } } }
  if ($ok -and $n2 -eq 0 -and $g2 -eq 0 -and $parseBad -eq 0) {
    $z = New-Object byte[] ((Get-Item -LiteralPath $bak).Length); [IO.File]::WriteAllBytes($bak, $z); Remove-Item -LiteralPath $bak -Force
    Write-Output "$line -> after exact=$n2 generic=$g2 jsonl_bad_lines=$parseBad OK"
  } else { $fail++; Write-Output "$line -> after exact=$n2 generic=$g2 jsonl_bad_lines=$parseBad replaced=$ok FAIL (backup mantido: $bak)" }
}
Write-Output "TOTAL_EXACT_HITS=$totalHits FAILS=$fail"
if ($fail) { exit 1 }